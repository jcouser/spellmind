-- Professions.lua: what the character's professions use (docs/milestone-9.md). The recipes and their
-- reagents can only be read while a profession's window is open, so they're kept as the player opens
-- them: SpellmindDB.recipes[charKey][itemID] = { { prof, name, learned } ... } (the recipes using that
-- item). The item tooltip line reads it ("used in your recipes: Light Armor Kit").
--
-- Read only: the window is the player's; nothing is crafted, nothing is opened.

local _, ns = ...
local PR = {}
ns.Professions = PR

PR.MAX_PER_ITEM = 8

local function Store()
	local db = ns.db
	if not db or not ns.State then return {} end
	if type(db.recipes) ~= "table" then db.recipes = {} end
	local key = ns.State.Key()
	if type(db.recipes[key]) ~= "table" then db.recipes[key] = {} end
	return db.recipes[key]
end

PR.MAX_RECIPES = 120

-- SpellmindDB.crafts[charKey][prof] = { at, skill, recipes = { { id, name, diff, reagents = { { item, need } } } } }:
-- the learned recipes as the profession's window last showed them.
local function Crafts()
	local db = ns.db
	if not db or not ns.State then return {} end
	if type(db.crafts) ~= "table" then db.crafts = {} end
	local key = ns.State.Key()
	if type(db.crafts[key]) ~= "table" then db.crafts[key] = {} end
	return db.crafts[key]
end

-- How hard a recipe is now, as the window colours it: "optimal" (orange: a sure skill-up), "medium"
-- (yellow), "easy" (green), "trivial" (grey), or nil when the client doesn't say.
PR.DIFF = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" }
PR.DIFF_RANK = { optimal = 0, medium = 1, easy = 2, trivial = 3 }
function PR.Difficulty(info)
	if type(info.relativeDifficulty) == "number" then return PR.DIFF[info.relativeDifficulty] end
	for _, k in ipairs({ "difficulty", "skillType" }) do
		local v = info[k]
		if v == "optimal" or v == "medium" or v == "easy" or v == "trivial" then return v end
	end
	return nil
end

-- The open profession's recipes into the store (the ones learned, and the ones the window lists as
-- not yet learned). Returns how many recipes were read.
function PR.Read()
	local T = rawget(_G, "C_TradeSkillUI")
	if type(T) ~= "table" or type(T.GetAllRecipeIDs) ~= "function" or type(T.GetRecipeSchematic) ~= "function" then return 0 end
	local base = ns.Try(T.GetBaseProfessionInfo)
	local prof = type(base) == "table" and type(base.professionName) == "string" and ns.State.Text(base.professionName) or nil
	if not prof then return 0 end
	local ids = ns.Try(T.GetAllRecipeIDs) or {}
	local store = Store()
	PR.MarkRead(prof)
	-- This profession's entries go first, so a recipe no longer listed doesn't linger.
	for item, list in pairs(store) do
		local keep = {}
		for _, r in ipairs(list) do if r.prof ~= prof then keep[#keep + 1] = r end end
		store[item] = #keep > 0 and keep or nil
	end
	local n = 0
	-- The learned recipes, each with how hard it is now (its skill-up chance) and its reagents.
	local crafts = { at = time(), skill = tonumber(base.skillLevel), recipes = {} }
	for _, rid in ipairs(ids) do
		local info = ns.Try(T.GetRecipeInfo, rid)
		local sch = ns.Try(T.GetRecipeSchematic, rid, false)
		if type(info) == "table" and type(sch) == "table" then
			n = n + 1
			local name = ns.State.Text(info.name) or ns.State.Text(sch.name) or "a recipe"
			local reagents = {}
			for _, slot in ipairs(type(sch.reagentSlotSchematics) == "table" and sch.reagentSlotSchematics or {}) do
				local first = true
				for _, rg in ipairs(type(slot) == "table" and type(slot.reagents) == "table" and slot.reagents or {}) do
					local item = type(rg) == "table" and tonumber(rg.itemID)
					if item then
						store[item] = store[item] or {}
						if #store[item] < PR.MAX_PER_ITEM then
							store[item][#store[item] + 1] = { prof = prof, name = name, learned = info.learned and true or false }
						end
						-- A slot's first reagent is the one it asks for (later ones are alternatives).
						if first then
							reagents[#reagents + 1] = { item = item, need = math.max(1, tonumber(slot.quantityRequired) or 1) }
							first = false
						end
					end
				end
			end
			if info.learned and #crafts.recipes < PR.MAX_RECIPES then
				crafts.recipes[#crafts.recipes + 1] = { id = rid, name = name, diff = PR.Difficulty(info), reagents = reagents }
			end
		end
	end
	Crafts()[prof] = crafts
	return n
end

-- Which of the character's professions have had their recipes read (their window opened once).
local function ReadSet()
	local db = ns.db
	if not db or not ns.State then return {} end
	if type(db.recipesRead) ~= "table" then db.recipesRead = {} end
	local key = ns.State.Key()
	if type(db.recipesRead[key]) ~= "table" then db.recipesRead[key] = {} end
	return db.recipesRead[key]
end
function PR.MarkRead(prof) ReadSet()[prof] = true end
function PR.WasRead(prof) return ReadSet()[prof] == true end

-- Gathering professions have no recipes; the others (crafting, Cooking, First Aid) do.
PR.GATHERING = { Skinning = true, Herbalism = true, Mining = true, Fishing = true }

-- Every crafting profession the character has was read: then "none of your recipes use it" is true.
-- names: the character's professions. Returns true, or false and the first one not read.
function PR.AllRead(names)
	local any = false
	for _, name in ipairs(names or {}) do
		if not PR.GATHERING[name] then
			any = true
			if not PR.WasRead(name) then return false, name end
		end
	end
	return any
end

-- The recipes of the character's that use an item: { { prof, name, learned } }, learned ones first.
function PR.Uses(itemID)
	local list = Store()[tonumber(itemID) or -1]
	if type(list) ~= "table" then return {} end
	local out = {}
	for _, r in ipairs(list) do out[#out + 1] = r end
	table.sort(out, function(a, b) if a.learned ~= b.learned then return a.learned end return a.name < b.name end)
	return out
end

---------------------------------------------------------------------------
-- What to do next (the Professions tab, docs/milestone-14.md)
---------------------------------------------------------------------------

-- The ranks (classic's rules): at a cap of 75 the next is Journeyman, trained from skill 50 and level
-- 10; 150 Expert (125, 20); 225 Artisan (200, 35). 300 is the top.
PR.RANKS = { [75] = { "Journeyman", 50, 10 }, [150] = { "Expert", 125, 20 }, [225] = { "Artisan", 200, 35 } }

-- The next rank for a skill: { name, skill, level, ready, short = { skill, level } }, or "max", or nil.
function PR.NextRank(rank, max)
	rank, max = tonumber(rank) or 0, tonumber(max) or 0
	if max >= 300 then return "max" end
	local r = PR.RANKS[max]
	if not r then return nil end
	local level = tonumber((ns.Try(UnitLevel, "player"))) or 1
	return { name = r[1], skill = r[2], level = r[3], ready = rank >= r[2] and level >= r[3],
		needSkill = rank < r[2], needLevel = level < r[3] }
end

-- How many of each item the bags hold: { [itemID] = count }.
function PR.BagCounts()
	local out = {}
	local C = rawget(_G, "C_Container")
	if type(C) ~= "table" then return out end
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		for slot = 1, tonumber((ns.Try(C.GetContainerNumSlots, bag))) or 0 do
			local it = ns.Try(C.GetContainerItemInfo, bag, slot)
			local id = type(it) == "table" and tonumber(it.itemID)
			if id then out[id] = (out[id] or 0) + (tonumber(it.stackCount) or 1) end
		end
	end
	return out
end

-- How many times a recipe can be made from the bags now.
function PR.Makes(recipe, counts)
	local n
	for _, rg in ipairs(recipe.reagents or {}) do
		local can = math.floor((counts[rg.item] or 0) / math.max(1, rg.need))
		n = n and math.min(n, can) or can
	end
	return n or 0
end

-- An item's name (the client's, when it has it).
function PR.ItemName(id)
	local name = ns.Try(C_Item and C_Item.GetItemInfo or GetItemInfo, id)
	return type(name) == "string" and name or ("item " .. tostring(id))
end

-- The recipes worth crafting for a skill-up: orange then yellow, the ones you can make first.
-- { list = { { name, diff, makes, reagents = { { item, need, have } } } }, read = true/false, skill } .
function PR.SkillUps(prof)
	local c = Crafts()[prof]
	if type(c) ~= "table" then return { read = PR.WasRead(prof) } end
	local counts = PR.BagCounts()
	local out = {}
	for _, r in ipairs(c.recipes or {}) do
		if r.diff == "optimal" or r.diff == "medium" then
			local rg = {}
			for _, x in ipairs(r.reagents or {}) do rg[#rg + 1] = { item = x.item, need = x.need, have = counts[x.item] or 0 } end
			out[#out + 1] = { name = r.name, diff = r.diff, makes = PR.Makes(r, counts), reagents = rg }
		end
	end
	table.sort(out, function(a, b)
		if a.diff ~= b.diff then return a.diff == "optimal" end
		if (a.makes > 0) ~= (b.makes > 0) then return a.makes > 0 end
		return a.name < b.name
	end)
	return { list = out, read = true, skill = c.skill, at = c.at }
end

-- The bags' materials for learned recipes: { { item, name, n, recipes = { { name, prof, makes } } } },
-- the most useful first (the ones that make something now).
function PR.Materials()
	local counts = PR.BagCounts()
	local by = {}
	for prof, c in pairs(Crafts()) do
		for _, r in ipairs(type(c) == "table" and c.recipes or {}) do
			local makes = PR.Makes(r, counts)
			for _, rg in ipairs(r.reagents or {}) do
				if (counts[rg.item] or 0) > 0 then
					local m = by[rg.item]
					if not m then
						m = { item = rg.item, name = PR.ItemName(rg.item), n = counts[rg.item], recipes = {} }
						by[rg.item] = m
					end
					m.recipes[#m.recipes + 1] = { name = r.name, prof = prof, makes = makes, diff = r.diff }
				end
			end
		end
	end
	local out = {}
	for _, m in pairs(by) do
		-- A skill-up first (orange, yellow), then what it makes most of.
		table.sort(m.recipes, function(a, b)
			local ra, rb = PR.DIFF_RANK[a.diff or ""] or 4, PR.DIFF_RANK[b.diff or ""] or 4
			if (a.makes > 0) ~= (b.makes > 0) then return a.makes > 0 end
			if ra ~= rb then return ra < rb end
			if a.makes ~= b.makes then return a.makes > b.makes end
			return a.name < b.name
		end)
		m.best = m.recipes[1] and m.recipes[1].makes or 0
		out[#out + 1] = m
	end
	table.sort(out, function(a, b) if a.best ~= b.best then return a.best > b.best end return a.name < b.name end)
	return out
end

function PR.Soon()
	if PR.pending then return end
	PR.pending = true
	C_Timer.After(1, function() PR.pending = nil; pcall(PR.Read) end)
end

ns.On("TRADE_SKILL_SHOW", function() PR.Soon() end)
ns.On("TRADE_SKILL_LIST_UPDATE", function() PR.Soon() end)
