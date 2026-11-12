-- Gold.lua: the Gold tab's numbers the game doesn't show (docs/milestone-14.md).
--
--   income   what came in and went out this session and today, and per hour, from the game's own
--            money changes (PLAYER_MONEY). Kept per character: SpellmindDB.gold[charKey] = { day,
--            earned, spent }. Counting starts when Spellmind is running.
--   costs    what's coming: spells due at the class trainer (Trainer.lua), a profession rank to
--            train, gear about to break.
--   worth    what the bags would fetch: safe to sell at a vendor (Gear.SellList, as the merchant card),
--            and on the auction house from Auctionator's last scan, through its public API
--            (Auctionator.API.v1), for what isn't soulbound.
--
-- Read only: nothing is sold, posted or bought.

local _, ns = ...
local GL = {}
ns.Gold = GL

GL.CALLER = "Spellmind" -- Auctionator's API asks who's calling
GL.PER_HOUR_AFTER = 600 -- a rate needs 10 minutes of play to mean anything
GL.AH_MAX = 5

local R = ns.R

local function Money() return tonumber((ns.Try(GetMoney))) or 0 end
local function Today() return date("%Y-%m-%d") end

local function Day()
	local db = ns.db
	if not db or not ns.State then return { earned = 0, spent = 0 } end
	if type(db.gold) ~= "table" then db.gold = {} end
	local key = ns.State.Key()
	local d = db.gold[key]
	if type(d) ~= "table" or d.day ~= Today() then
		d = { day = Today(), earned = 0, spent = 0 }
		db.gold[key] = d
	end
	return d
end

function GL.Start()
	R.gold = { at = time(), last = Money(), earned = 0, spent = 0 }
	Day()
end

-- A money change: in or out, for the session and the day.
function GL.OnMoney()
	local s = R.gold
	if not s then GL.Start(); return end
	local now = Money()
	local delta = now - (s.last or now)
	s.last = now
	if delta == 0 then return end
	local d = Day()
	if delta > 0 then
		s.earned, d.earned = s.earned + delta, (d.earned or 0) + delta
	else
		s.spent, d.spent = s.spent + -delta, (d.spent or 0) + -delta
	end
end

-- { session = { earned, spent, net, perHour? }, today = { earned, spent, net } }.
function GL.Income()
	local s = R.gold or { at = time(), earned = 0, spent = 0 }
	local d = Day()
	local secs = math.max(0, time() - (s.at or time()))
	local net = s.earned - s.spent
	return {
		session = { earned = s.earned, spent = s.spent, net = net, secs = secs,
			perHour = secs >= GL.PER_HOUR_AFTER and math.floor(net * 3600 / secs) or nil },
		today = { earned = d.earned or 0, spent = d.spent or 0, net = (d.earned or 0) - (d.spent or 0) },
	}
end

-- What's coming: { { label, copper?, note } }, and the known total.
function GL.Costs()
	local out, total = {}, 0
	if ns.Trainer then
		local ok, p = pcall(ns.Trainer.Plan)
		if ok and p and #p.due > 0 then
			out[#out + 1] = { label = #p.due .. " spell" .. (#p.due > 1 and "s" or "") .. " at your trainer", copper = p.total }
			total = total + p.total
		end
	end
	local skills = ns.State and ns.State.Collect and select(2, pcall(ns.State.Collect.skills))
	for _, kv in ipairs(type(skills) == "table" and skills._o or {}) do
		if kv[1] == "prof" then
			for _, p in ipairs(kv[2] or {}) do
				local t = {}
				for _, f in ipairs(p._o or {}) do t[f[1]] = f[2] end
				local nr = ns.Professions and ns.Professions.NextRank(t.rank, t.max)
				if type(nr) == "table" and nr.ready then
					out[#out + 1] = { label = nr.name .. " " .. tostring(t.name), note = "train now: the price is at the trainer" }
				end
			end
		end
	end
	-- Gear about to break: repairs. Their cost shows only at a merchant who repairs.
	local gear = ns.State and ns.State.Collect and select(2, pcall(ns.State.Collect.gear))
	local worst, broken = nil, 0
	for _, kv in ipairs(type(gear) == "table" and gear._o or {}) do
		if kv[1] == "items" then
			for _, it in ipairs(kv[2] or {}) do
				for _, f in ipairs(it._o or {}) do
					if f[1] == "dur" and type(f[2]) == "table" and (tonumber(f[2][2]) or 0) > 0 then
						local pct = math.floor(f[2][1] / f[2][2] * 100 + 0.5)
						if pct < 100 then broken = broken + 1 end
						if not worst or pct < worst then worst = pct end
					end
				end
			end
		end
	end
	if worst and worst < 60 then
		out[#out + 1] = { label = "Repairs", note = broken .. " item" .. (broken > 1 and "s" or "") .. " worn, the worst at " .. worst .. "%" }
	end
	return out, total
end

-- Auctionator's public API, when it's loaded.
local function AH()
	local A = rawget(_G, "Auctionator")
	local api = type(A) == "table" and type(A.API) == "table" and A.API.v1
	if type(api) ~= "table" or type(api.GetAuctionPriceByItemID) ~= "function" then return nil end
	return api
end
GL.HasAH = function() return AH() ~= nil end

-- What the bags would fetch on the auction house: { total, list = { { name, n, copper } }, priced },
-- or nil without Auctionator. Soulbound items and grey junk can't be sold there and are left out.
function GL.AHWorth()
	local api = AH()
	if not api then return nil end
	local C = rawget(_G, "C_Container")
	local by, order = {}, {}
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		for slot = 1, tonumber((ns.Try(C.GetContainerNumSlots, bag))) or 0 do
			local it = ns.Try(C.GetContainerItemInfo, bag, slot)
			local id = type(it) == "table" and tonumber(it.itemID)
			if id and not it.isBound and (it.quality or 1) > 0 then
				if not by[id] then by[id] = { id = id, name = it.itemName or ns.Professions.ItemName(id), n = 0 }; order[#order + 1] = id end
				by[id].n = by[id].n + (tonumber(it.stackCount) or 1)
			end
		end
	end
	local list, total = {}, 0
	for _, id in ipairs(order) do
		local price = tonumber((ns.Try(api.GetAuctionPriceByItemID, GL.CALLER, id)))
		if price and price > 0 then
			local e = by[id]
			e.copper = price * e.n
			total = total + e.copper
			list[#list + 1] = e
		end
	end
	table.sort(list, function(a, b) return a.copper > b.copper end)
	return { total = total, list = list, priced = #list }
end

ns.On("PLAYER_LOGIN", function() C_Timer.After(1, GL.Start) end)
ns.On("PLAYER_MONEY", function() GL.OnMoney() end)
