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
	for _, rid in ipairs(ids) do
		local info = ns.Try(T.GetRecipeInfo, rid)
		local sch = ns.Try(T.GetRecipeSchematic, rid, false)
		if type(info) == "table" and type(sch) == "table" then
			n = n + 1
			local name = ns.State.Text(info.name) or ns.State.Text(sch.name) or "a recipe"
			for _, slot in ipairs(type(sch.reagentSlotSchematics) == "table" and sch.reagentSlotSchematics or {}) do
				for _, rg in ipairs(type(slot) == "table" and type(slot.reagents) == "table" and slot.reagents or {}) do
					local item = type(rg) == "table" and tonumber(rg.itemID)
					if item then
						store[item] = store[item] or {}
						if #store[item] < PR.MAX_PER_ITEM then
							store[item][#store[item] + 1] = { prof = prof, name = name, learned = info.learned and true or false }
						end
					end
				end
			end
		end
	end
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

function PR.Soon()
	if PR.pending then return end
	PR.pending = true
	C_Timer.After(1, function() PR.pending = nil; pcall(PR.Read) end)
end

ns.On("TRADE_SKILL_SHOW", function() PR.Soon() end)
ns.On("TRADE_SKILL_LIST_UPDATE", function() PR.Soon() end)
