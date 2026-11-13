-- Trainer.lua: what the class trainer offers (docs/milestone-10.md). On Forever the spellbook lists no
-- coming spells (seen in game), so the trainer's own list is read when its window opens and kept:
-- SpellmindDB.chars[key].trainer = { at, services = { { name, rank, kind, cost, level } } }.
--
--   due    services learnable now (the trainer said "available", or a later one the character has
--          reached the level for since), not yet in the spellbook
--   soon   the next ones by level
--
-- Read only: nothing is learned, no filter is changed. A profession trainer's list isn't kept here.

local _, ns = ...
local TR = {}
ns.Trainer = TR

TR.MAX = 80
TR.SOON_MAX = 8

local function Me()
	return ns.State and ns.State.Me and ns.State.Me() or nil
end

local function Level() return tonumber((ns.Try(UnitLevel, "player"))) or 1 end

-- A service's rank from the game's tooltip data for it ("Rank 3" beside its name), or nil.
function TR.TooltipRank(i)
	local T = rawget(_G, "C_TooltipInfo")
	local data = T and type(T.GetTrainerService) == "function" and select(2, pcall(T.GetTrainerService, i)) or nil
	for k, line in ipairs(type(data) == "table" and type(data.lines) == "table" and data.lines or {}) do
		if k > 3 then break end
		for _, t in ipairs({ line.rightText, line.leftText }) do
			local r = type(t) == "string" and tonumber(t:match("Rank (%d+)"))
			if r then return r end
		end
	end
	return nil
end

-- The trainer's list now into the store (the class trainer only). Returns how many services.
function TR.Read()
	if type(GetNumTrainerServices) ~= "function" then return 0 end
	if type(IsTradeskillTrainer) == "function" and ns.Try(IsTradeskillTrainer) then return 0 end
	local me = Me()
	if not me then return 0 end
	local list = {}
	for i = 1, math.min(tonumber((ns.Try(GetNumTrainerServices))) or 0, TR.MAX) do
		local name, sub, kind = ns.Try(GetTrainerServiceInfo, i)
		if type(name) == "string" and name ~= "" and kind ~= "header" then
			-- The rank: the service's subtext ("Rank 3"); on Forever that came back empty (seen in game:
			-- Eviscerate 3 taken for the Eviscerate 2 already known), so the tooltip's text too.
			local rank = type(sub) == "string" and tonumber(sub:match("(%d+)")) or nil
			rank = rank or tonumber(name:match("%(Rank (%d+)%)")) or TR.TooltipRank(i)
			list[#list + 1] = { name = ns.State.Text(name), rank = rank, kind = kind,
				cost = tonumber((ns.Try(GetTrainerServiceCost, i))) or 0, level = tonumber((ns.Try(GetTrainerServiceLevelReq, i))) or 0 }
		end
	end
	-- Only a class trainer's list (the review: a weapon master's "Swords, Bows" replaced it): one with a
	-- ranked spell, or a spell the spellbook has.
	if #list > 0 and TR.IsClassList(list) then me.trainer = { at = time(), services = list } end
	return #list
end

-- The spellbook's known spells: { [name] = highest rank (0 for a spell without ranks) }.
local function Known()
	local out = {}
	local s = ns.State and ns.State.Collect and ns.State.Collect.spells and select(2, pcall(ns.State.Collect.spells))
	for _, kv in ipairs(type(s) == "table" and s._o or {}) do
		if kv[1] == "tabs" then
			for _, tab in ipairs(kv[2] or {}) do
				for _, f in ipairs(tab._o or {}) do
					if f[1] == "list" then
						for _, sp in ipairs(f[2] or {}) do
							local t = {}
							for _, g in ipairs(sp._o or {}) do t[g[1]] = g[2] end
							if t.name then out[t.name] = math.max(out[t.name] or 0, tonumber(t.rank) or 0) end
						end
					end
				end
			end
		end
	end
	return out
end

-- A class trainer's list: a ranked spell in it, or a spell the spellbook already has. A weapon
-- master's ("Swords", "Bows") or a riding trainer's has neither.
function TR.IsClassList(list)
	local known = Known()
	for _, s in ipairs(list) do
		if s.rank or known[s.name] then return true end
	end
	return false
end

-- What's due and what's coming, from the kept list: due = learnable at this level and not known
-- (by name and rank); soon = the next ones above this level, by level. known: { [name] = rank },
-- given by State's spells part (which calls TR.ForState while it builds), else read here.
function TR.Plan(known)
	local me = Me()
	local t = me and me.trainer
	if type(t) ~= "table" or type(t.services) ~= "table" then return nil end
	local level = Level()
	known = known or Known()
	local due, soon, total = {}, {}, 0
	for _, s in ipairs(t.services) do
		local have = known[s.name]
		-- The trainer's own word first ("used" is learned). Learned since the visit: the book has that
		-- rank, or, for a service with no rank read, the book has the spell with no rank at all (a known
		-- Eviscerate 2 is no proof of an unranked "Eviscerate" being learned: seen in game).
		local learned = s.kind == "used" or (have ~= nil and ((s.rank ~= nil and have >= s.rank) or (s.rank == nil and have == 0)))
		if not learned then
			if (tonumber(s.level) or 0) <= level then
				due[#due + 1] = s
				total = total + (tonumber(s.cost) or 0)
			else
				soon[#soon + 1] = s
			end
		end
	end
	table.sort(due, function(a, b) return (a.level or 0) < (b.level or 0) end)
	table.sort(soon, function(a, b) return (a.level or 0) < (b.level or 0) end)
	while #soon > TR.SOON_MAX do table.remove(soon) end
	return { at = t.at, due = due, soon = soon, total = total }
end

-- "Kick (rank 2)".
function TR.Label(s)
	return (s.name or "?") .. (s.rank and (" (rank " .. s.rank .. ")") or "")
end

-- For the spells part (State.lua): { at, due = { {name, rank, cost} }, soon = { {name, rank, level} } }.
function TR.ForState(known)
	local p = TR.Plan(known)
	if not p then return nil end
	local O = ns.State.JSON.O
	local due, soon = {}, {}
	for i, s in ipairs(p.due) do if i <= 10 then due[#due + 1] = O("name", s.name, "rank", s.rank, "cost", s.cost) end end
	for i, s in ipairs(p.soon) do if i <= 10 then soon[#soon + 1] = O("name", s.name, "rank", s.rank, "level", s.level) end end
	return O("at", p.at, "due", due, "soon", soon)
end

---------------------------------------------------------------------------
-- At the trainer: "Spellmind: what to train" beside its window
---------------------------------------------------------------------------

function TR.Text()
	local p = TR.Plan()
	if not p then return "Spellmind hasn't read this trainer yet: close and open its window again." end
	local money = tonumber((ns.Try(GetMoney))) or 0
	local M = ns.GearUI and ns.GearUI.Money or function(c) return tostring(c) .. "c" end
	local lines = {}
	if #p.due > 0 then
		lines[#lines + 1] = "You can learn now, |cffffd100" .. M(p.total) .. "|r in all" .. (money < p.total and (" |cffff6060(you have " .. M(money) .. ")|r") or "") .. ":"
		lines[#lines + 1] = ""
		for _, s in ipairs(p.due) do lines[#lines + 1] = "• " .. ns.Escape(TR.Label(s)) .. ": " .. M(s.cost or 0) end
	else
		lines[#lines + 1] = "Nothing new to learn at your level."
	end
	if #p.soon > 0 then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "Coming next:"
		for _, s in ipairs(p.soon) do lines[#lines + 1] = "• level " .. (s.level or "?") .. ": " .. ns.Escape(TR.Label(s)) end
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "|cff888888Ask more: which are worth it for how you play.|r"
	return table.concat(lines, "\n")
end

function TR.ShowButton()
	if not ns.Marks or not ns.Marks.On("trainer") then return end
	local f = rawget(_G, "ClassTrainerFrame")
	if type(f) ~= "table" then return end
	if not TR.button then
		if not (ns.GearUI and ns.GearUI.Button) then return end
		local b = ns.GearUI.Button(f, "Spellmind: what to train", 160)
		b:SetPoint("TOPLEFT", f, "TOPRIGHT", 4, -36)
		b:SetScript("OnClick", function()
			ns.Marks.ShowText(f, "Spellmind: what to train", TR.Text(), { owner = f })
		end)
		TR.button = b
	end
	TR.button:Show()
end

local function Seen()
	pcall(TR.Read)
	if ns.State and ns.State.Dirty then ns.State.Dirty() end
	pcall(TR.ShowButton)
end

ns.On("TRAINER_SHOW", function() C_Timer.After(0.2, Seen) end)
-- The filter changed or a spell was learned: read again once, however many updates come.
ns.On("TRAINER_UPDATE", function()
	if TR.updatePending then return end
	TR.updatePending = true
	C_Timer.After(0.3, function() TR.updatePending = nil; pcall(TR.Read) end)
end)
ns.On("TRAINER_CLOSED", function()
	if ns.Marks and ns.Marks.card and ns.Marks.card.owner == rawget(_G, "ClassTrainerFrame") then ns.Marks.card:Hide() end
end)
