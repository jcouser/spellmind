-- World.lua: where things are, for the AI's "who sells ammo here" and "how do I get to Westfall"
-- (docs/milestone-17.md). The model's memory named a vendor the player couldn't find and a mountain
-- pass that doesn't exist (seen in game, 2026-11-12), so these come from the game:
--
--   hearth    where the hearthstone goes (GetBindLocation)
--   flights   the flight paths the character knows, noted at each flight master's map
--   npcs      NPCs the character has used (a vendor, trainer, flight master, innkeeper, banker), noted
--             when their window opens: name, title ("General Supplies"), zone, where (the player's
--             spot then: they're within reach), what they offer, and a vendor's goods. Account-wide:
--             a town's vendors are the same for every character of that faction.
--   QuestieDB, only when it's installed: the zone's other service NPCs (its public API, read at
--             runtime; nothing of it is kept). Spellmind works fully without it.
--
-- Read only: nothing is bought, set or flown.

local _, ns = ...
local WD = {}
ns.World = WD

WD.SELLS_MAX = 40 -- items kept a vendor
WD.NPCS_MAX = 20 -- NPCs in the part
WD.SELLS_SENT = 10 -- a vendor's items in the part
WD.FLIGHTS_MAX = 40

local function Me() return ns.State and ns.State.Me and ns.State.Me() or nil end

local function Store()
	local db = ns.db
	if not db then return {} end
	if type(db.npcs) ~= "table" then db.npcs = {} end
	return db.npcs
end

local function Faction()
	local f = ns.Try(UnitFactionGroup, "player")
	return type(f) == "string" and f or "Neutral"
end

-- The player's spot now: map id, zone name, x and y in map percent.
function WD.Here()
	local M = rawget(_G, "C_Map")
	local map = M and ns.Try(M.GetBestMapForUnit, "player")
	local x, y
	if type(map) == "number" then
		local pos = ns.Try(M.GetPlayerMapPosition, map, "player")
		if type(pos) == "table" then
			if type(pos.GetXY) == "function" then x, y = pos:GetXY() else x, y = pos.x, pos.y end
		end
	end
	return { map = map, zone = ns.State.Text(ns.Try(GetRealZoneText)), sub = ns.State.Text(ns.Try(GetSubZoneText)),
		x = tonumber(x) and math.floor(x * 1000 + 0.5) / 10 or nil, y = tonumber(y) and math.floor(y * 1000 + 0.5) / 10 or nil }
end

-- The NPC the player is talking to: { id, name, sub } (its title from the game's tooltip data).
local function Talking()
	local guid = ns.Try(UnitGUID, "npc")
	if type(guid) ~= "string" then return nil end
	local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
	if kind ~= "Creature" or not tonumber(id) then return nil end
	-- The name and title from the NPC's own tooltip data (UnitName is never called: the addon reads
	-- no character's name, and its tests hold it to that).
	local T = rawget(_G, "C_TooltipInfo")
	local data = T and type(T.GetUnit) == "function" and select(2, pcall(T.GetUnit, "npc")) or nil
	local lines = type(data) == "table" and type(data.lines) == "table" and data.lines or {}
	local name = type(lines[1]) == "table" and lines[1].leftText
	if type(name) ~= "string" or name == "" then return nil end
	local sub
	local second = lines[2]
	local text = type(second) == "table" and second.leftText
	if type(text) == "string" and text ~= "" and not text:find("^Level") then sub = ns.State.Text((text:gsub("^<", ""):gsub(">$", ""))) end
	return { id = tonumber(id), name = ns.State.Text(name), sub = sub }
end

-- Note the NPC being used: what they offer (does = "vendor", "trainer", "flight", "innkeeper",
-- "banker", "repair"), where, and for a vendor what they sell. Returns the entry.
function WD.Note(does, extra)
	local who = Talking()
	if not who then return nil end
	local here = WD.Here()
	local store = Store()
	local e = store[who.id] or {}
	e.name, e.sub, e.faction, e.at = who.name, who.sub or e.sub, Faction(), time()
	e.zone, e.subzone, e.map, e.x, e.y = here.zone, here.sub, here.map, here.x, here.y
	e.does = type(e.does) == "table" and e.does or {}
	e.does[does] = true
	for k, v in pairs(extra or {}) do e[k] = v end
	store[who.id] = e
	if ns.State and ns.State.Dirty then ns.State.Dirty() end
	return e
end

-- A vendor's goods: their names, ammo and food first (what's asked for most).
local function Goods()
	local out, rest = {}, {}
	local n = tonumber((ns.Try(GetMerchantNumItems))) or 0
	for i = 1, math.min(n, 80) do
		local name = ns.Try(GetMerchantItemInfo, i)
		local link = ns.Try(GetMerchantItemLink, i)
		if type(name) == "string" and name ~= "" then
			-- GetItemInfoInstant's sixth return (ns.Try keeps four): the item class.
			local classID
			if type(link) == "string" and C_Item and type(C_Item.GetItemInfoInstant) == "function" then
				local r = { pcall(C_Item.GetItemInfoInstant, link) }
				if r[1] then classID = r[7] end
			end
			local first = classID == 6 or classID == 0 -- projectiles, consumables
			table.insert(first and out or rest, ns.State.Text(name))
		end
	end
	for _, r in ipairs(rest) do out[#out + 1] = r end
	while #out > WD.SELLS_MAX do table.remove(out) end
	return out
end

function WD.OnMerchant()
	local repair = ns.Try(CanMerchantRepair) and true or false
	local e = WD.Note("vendor", { sells = Goods() })
	if e and repair then e.does.repair = true end
end

-- The flight master's map: the paths this character knows (their names), and the master noted.
function WD.OnTaxi()
	local me = Me()
	if not me then return end
	me.flights = type(me.flights) == "table" and me.flights or {}
	local n = tonumber((ns.Try(NumTaxiNodes))) or 0
	for i = 1, math.min(n, 120) do
		local name, kind = ns.Try(TaxiNodeName, i), ns.Try(TaxiNodeGetType, i)
		if type(name) == "string" and name ~= "" and (kind == "CURRENT" or kind == "REACHABLE") then me.flights[ns.State.Text(name)] = true end
	end
	WD.Note("flight")
end

-- The innkeeper's and banker's own options in a gossip window (the game's option types).
function WD.OnGossip()
	local G = rawget(_G, "C_GossipInfo")
	local opts = G and type(G.GetOptions) == "function" and ns.Try(G.GetOptions) or {}
	for _, o in ipairs(type(opts) == "table" and opts or {}) do
		local t = type(o) == "table" and (o.type or o.icon) or nil
		if t == "binder" then WD.Note("innkeeper") elseif t == "banker" then WD.Note("banker") end
	end
end

-- The flight paths known: their names, sorted.
function WD.Flights()
	local me = Me()
	local out = {}
	for name in pairs(me and type(me.flights) == "table" and me.flights or {}) do out[#out + 1] = name end
	table.sort(out)
	while #out > WD.FLIGHTS_MAX do table.remove(out) end
	return out
end

---------------------------------------------------------------------------
-- QuestieDB, when installed: the zone's other service NPCs (one pass over its NPCs, a few hundred a
-- frame, once a session). Without it, the character's own memory is all there is.
---------------------------------------------------------------------------

WD.SCAN_PER_TICK = 400

local function DB()
	local L = rawget(_G, "LibQuestieDB")
	if type(L) ~= "table" or type(L.Npc) ~= "table" or type(L.Npc.GetAllIds) ~= "function" then return nil end
	if type(L.RequireContract) == "function" and not ns.Try(L.RequireContract, 4) then return nil end
	return L
end

-- The service flags QuestieDB uses on this client, and their words.
local function Services(L)
	local F = type(L.Enum) == "table" and type(L.Enum.npcFlags) == "table" and L.Enum.npcFlags or {}
	local out = {}
	for key, word in pairs({ VENDOR = "vendor", TRAINER = "trainer", FLIGHT_MASTER = "flight", INNKEEPER = "innkeeper", BANKER = "banker", REPAIR = "repair" }) do
		if tonumber(F[key]) then out[#out + 1] = { tonumber(F[key]), word } end
	end
	return out
end

local function Has(flags, bit)
	return math.floor((tonumber(flags) or 0) / bit) % 2 == 1
end

-- { [areaID] = { npcIDs } } of service NPCs friendly to the character, once the pass is done.
function WD.Index()
	if WD.index then return WD.index end
	local L = DB()
	if not L or WD.scanning then return nil end
	local ok, ids = pcall(L.Npc.GetAllIds)
	if not ok or type(ids) ~= "table" then return nil end
	WD.scanning = true
	local services = Services(L)
	local mine = Faction() == "Horde" and "H" or "A"
	local index, i = {}, 1
	local function step()
		local stop = math.min(#ids, i + WD.SCAN_PER_TICK - 1)
		for k = i, stop do
			local id = ids[k]
			local flags = ns.Try(L.Npc.npcFlags, id)
			local any = false
			for _, s in ipairs(services) do if Has(flags, s[1]) then any = true; break end end
			if any then
				local friendly = ns.Try(L.Npc.friendlyToFaction, id)
				local zone = tonumber((ns.Try(L.Npc.zoneID, id)))
				if zone and (friendly == nil or tostring(friendly):find(mine, 1, true)) then
					index[zone] = index[zone] or {}
					table.insert(index[zone], id)
				end
			end
		end
		i = stop + 1
		if i > #ids then WD.index, WD.scanning = index, nil else C_Timer.After(0, step) end
	end
	step()
	return WD.index
end

-- The zone's area ID for a ui map (QuestieDB's own table), or nil.
-- By the map's name (QuestieDB's own table is Lua source text, not a table: seen in game), through
-- the area lookup Dungeons.lua already does by name.
local function AreaOf(L, map)
	local M = rawget(_G, "C_Map")
	local info = M and ns.Try(M.GetMapInfo, map)
	local name = type(info) == "table" and info.name
	if type(name) ~= "string" or name == "" or not ns.Dungeons then return nil end
	return ns.Dungeons.AreaOf(name)
end

-- QuestieDB's service NPCs in the player's zone: { name, sub, does, x, y } (not the remembered ones).
local function FromDB(here, known)
	local L = DB()
	if not L or type(here.map) ~= "number" then return {} end
	local index = WD.Index()
	local area = index and AreaOf(L, here.map)
	if not area then return {} end
	local services = Services(L)
	local out = {}
	for _, id in ipairs(index[area] or {}) do
		if not known[id] then
			local name = ns.Try(L.Npc.name, id)
			if type(name) == "string" and name ~= "" then
				local spawns = ns.Try(L.Npc.spawns, id)
				local at = type(spawns) == "table" and type(spawns[area]) == "table" and spawns[area][1]
				local does = {}
				local flags = ns.Try(L.Npc.npcFlags, id)
				for _, s in ipairs(services) do if Has(flags, s[1]) then does[#does + 1] = s[2] end end
				local sub = ns.Try(L.Npc.subName, id)
				out[#out + 1] = { name = ns.State.Text(name), sub = type(sub) == "string" and ns.State.Text(sub) or nil, does = does,
					x = type(at) == "table" and tonumber(at[1]) or nil, y = type(at) == "table" and tonumber(at[2]) or nil }
			end
		end
	end
	return out
end

---------------------------------------------------------------------------
-- The part
---------------------------------------------------------------------------

local function Dist(here, n)
	if not (here.x and here.y and n.x and n.y) then return 1e9 end
	return (here.x - n.x) ^ 2 + (here.y - n.y) ^ 2
end

-- The NPCs worth knowing here: the character's own (same zone, their faction or neutral), then
-- QuestieDB's, nearest first, at most NPCS_MAX.
function WD.Nearby()
	local here = WD.Here()
	local list, known = {}, {}
	local mine = Faction()
	for id, e in pairs(Store()) do
		if type(e) == "table" and e.zone == here.zone and (e.faction == mine or e.faction == "Neutral" or e.faction == nil) then
			known[id] = true
			local does = {}
			for k in pairs(e.does or {}) do does[#does + 1] = k end
			table.sort(does)
			list[#list + 1] = { name = e.name, sub = e.sub, does = does, x = e.x, y = e.y, sells = e.sells, seen = true }
		end
	end
	for _, n in ipairs(FromDB(here, known)) do list[#list + 1] = n end
	table.sort(list, function(a, b) return Dist(here, a) < Dist(here, b) end)
	while #list > WD.NPCS_MAX do table.remove(list) end
	-- Then by name, so the part stays the same as the player walks (the review: it changed with every
	-- step and was sent again and again). char.loc has the player's spot for distances.
	table.sort(list, function(a, b) return tostring(a.name) < tostring(b.name) end)
	return list, here
end

-- The world part (State.lua).
function WD.Part()
	local O = ns.State.JSON.O
	local npcs, here = WD.Nearby()
	local list = {}
	for _, n in ipairs(npcs) do
		local sells
		if type(n.sells) == "table" and #n.sells > 0 then
			sells = {}
			for i = 1, math.min(#n.sells, WD.SELLS_SENT) do sells[i] = n.sells[i] end
		end
		list[#list + 1] = O("name", n.name, "sub", n.sub, "does", #n.does > 0 and n.does or nil, "x", n.x, "y", n.y,
			"sells", sells, "seen", n.seen and true or nil)
	end
	local flights = WD.Flights()
	local hearth = ns.State.Text(ns.Try(GetBindLocation))
	return O("v", 1, "zone", here.zone, "sub", here.sub, "hearth", hearth,
		"flights", #flights > 0 and flights or nil, "npcs", #list > 0 and list or nil)
end

ns.On("MERCHANT_SHOW", function() pcall(WD.OnMerchant) end)
ns.On("TAXIMAP_OPENED", function() pcall(WD.OnTaxi) end)
ns.On("TRAINER_SHOW", function() pcall(WD.Note, "trainer") end)
ns.On("BANKFRAME_OPENED", function() pcall(WD.Note, "banker") end)
ns.On("GOSSIP_SHOW", function() pcall(WD.OnGossip) end)
