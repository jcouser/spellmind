-- Gear.lua: the gear advisor's local side (docs/features.md §3.2, docs/milestone-9.md): weak slots,
-- upgrades the character can already get (rewards of quests in the log, wearables in the bags), the
-- likely pick of a quest's reward choice, and what's safe to sell. All from the game's own data, no
-- AI; the "why" and "how to get it" questions go to the AI from the Advisor panel.
--
-- No invented scores: an item counts as an upgrade only when it can be used and is clearly ahead
-- (an empty slot, or a higher item level with more of the class's main stats than it loses). The
-- pick of a reward choice is labelled "likely": the AI can say why, or why not.

local _, ns = ...
local G = {}
ns.Gear = G
local R = ns.R

G.SLOT_NAMES = { "Head", "Neck", "Shoulder", "Shirt", "Chest", "Waist", "Legs", "Feet", "Wrist", "Hands", "Ring", "Ring",
	"Trinket", "Trinket", "Back", "Main Hand", "Off Hand", "Ranged", "Tabard" }
G.COSMETIC = { [4] = true, [19] = true } -- shirt, tabard
-- The stats that matter most to each class, for comparing two items of a slot (a rough order, not a
-- score: sta counts for everyone).
G.MAIN = {
	ROGUE = { agi = 2, sta = 1, str = 0.5, ap = 0.5, dps = 3 }, HUNTER = { agi = 2, sta = 1, int = 0.5, ap = 0.5, dps = 3 },
	WARRIOR = { str = 2, sta = 1.5, agi = 1, ap = 0.5, dps = 3, armor = 0.05 }, PALADIN = { str = 2, sta = 1.5, int = 1, armor = 0.05, dps = 2 },
	SHAMAN = { int = 1.5, str = 1, agi = 1, sta = 1, sp = 1, dps = 2 }, DRUID = { agi = 1.5, int = 1.5, str = 1, sta = 1, sp = 1 },
	MAGE = { int = 2, sta = 1, spi = 0.5, sp = 1.5 }, WARLOCK = { int = 2, sta = 1.5, spi = 0.5, sp = 1.5 },
	PRIEST = { int = 2, spi = 1, sta = 1, sp = 1, heal = 1 },
}
G.WEAK_ILVL = 5 -- item levels below the character's level that make a slot weak

local function Class()
	local _, file = ns.Try(UnitClass, "player")
	return type(file) == "string" and file or "WARRIOR"
end

local function Level() return tonumber((ns.Try(UnitLevel, "player"))) or 1 end

-- GetItemInfo's returns (pcall: ns.Try keeps four): name 2, link 3, quality 4, ilvl 5, req 6, type 7,
-- sub 8, equipLoc 10, icon 11, sell 12, classID 13.
local function Info(link)
	local r = C_Item and type(C_Item.GetItemInfo) == "function" and { pcall(C_Item.GetItemInfo, link) } or {}
	if not r[1] or not r[2] then return nil end
	local dil = ns.Try(C_Item.GetDetailedItemLevelInfo, link)
	return { name = r[2], link = r[3] or link, q = r[4], ilvl = (type(dil) == "number" and dil > 0) and dil or r[5], req = r[6],
		sub = r[8], equipLoc = r[10], icon = r[11], sell = r[12], classID = r[13] }
end

-- Usable now: no requirement in red in the game's own tooltip data (skill, level, armour, class).
function G.Usable(link)
	local data = C_TooltipInfo and type(C_TooltipInfo.GetHyperlink) == "function" and select(2, pcall(C_TooltipInfo.GetHyperlink, link)) or nil
	return #ns.Tooltip.RedTexts(type(data) == "table" and data or nil) == 0
end

-- The worn item of a slot: { link, info, stats } or nil.
local function Worn(slot)
	local link = ns.Try(GetInventoryItemLink, "player", slot)
	if type(link) ~= "string" then return nil end
	return { link = link, info = Info(link), stats = ns.State.ItemStats(link) }
end

-- The player's guide's stat priority (Guide.lua) as weights, when it has one (docs/milestone-16.md):
-- the first stat counts 2, the last 0.8, times what one point of it is worth (1 Agility is about 2
-- Attack Power; 1 Hit or Crit is a whole percent on classic items). Weapon damage and armour keep the
-- class's own weights: guides list stats, not those. Stats it doesn't name count nothing.
G.GUIDE_STATS = {
	{ "agi", "agility" }, { "str", "strength" }, { "sta", "stamina" }, { "int", "intellect" }, { "spi", "spirit" },
	{ "rap", "ranged attack power" }, { "ap", "attack power" }, { "hit", "hit" }, { "crit", "crit" }, { "sp", "spell power" },
	{ "sp", "spell damage" }, { "heal", "healing" }, { "mp5", "mana" }, { "def", "defense" }, { "dodge", "dodge" },
	{ "parry", "parry" }, { "block", "block" }, { "armor", "armor" },
}
G.PER_POINT = { agi = 1, str = 1, sta = 1, int = 1, spi = 1, ap = 0.5, rap = 0.5, hit = 10, crit = 10, sp = 1.2, heal = 0.6,
	mp5 = 2, def = 1, dodge = 10, parry = 10, block = 1, armor = 0.05 }

-- The guide's stat names into keys, in its order (a stat once: "Attack Power" isn't also "Ranged").
function G.GuideOrder(stats)
	local out, seen = {}, {}
	for _, s in ipairs(stats or {}) do
		local low = tostring(s):lower()
		for _, k in ipairs(G.GUIDE_STATS) do
			if not seen[k[1]] and low:find(k[2], 1, true) and not (k[1] == "ap" and low:find("ranged", 1, true)) then
				seen[k[1]] = true
				out[#out + 1] = k[1]
				break
			end
		end
	end
	return out
end

function G.Weights()
	local base = G.MAIN[Class()] or G.MAIN.WARRIOR
	local g = ns.Guide and ns.Guide.Get()
	local stats = g and g.plan and g.plan.stats
	local order = G.GuideOrder(stats)
	if #order < 2 then return base, false end
	if G.weights and G.weightsAt == g.at then return G.weights, true end
	local w = { dps = base.dps, armor = base.armor }
	for i, k in ipairs(order) do
		local rank = 2 - 1.2 * (i - 1) / (#order - 1)
		w[k] = (G.PER_POINT[k] or 1) * rank
	end
	G.weights, G.weightsAt = w, g.at
	return w, true
end

-- How much of the class's main stats an item has (to compare two of the same slot), and its stats.
-- With a guide, its stat priority decides (G.Weights).
function G.Weight(link)
	local w, total = G.Weights(), 0
	local st = ns.State.ItemStats(link)
	for k, v in pairs(st) do total = total + (w[k] or 0) * (tonumber(v) or 0) end
	return total, st
end

-- The slot an item would go in (the emptier or weaker of a pair), or nil when it isn't wearable.
local function SlotFor(info)
	local slots = info and ns.Tooltip.SLOTS[info.equipLoc or ""]
	if not slots then return nil end
	local best, bestW
	for _, s in ipairs(slots) do
		if not ns.Try(GetInventoryItemID, "player", s) then return s end
		if info.equipLoc ~= "INVTYPE_WEAPON" or s == 16 then -- a one-hander is compared with the main hand
			local wl = ns.Try(GetInventoryItemLink, "player", s)
			local wv = wl and G.Weight(wl) or 0
			if not bestW or wv < bestW then best, bestW = s, wv end
		end
	end
	return best
end

-- A weapon's speed (seconds), from the game's tooltip data ("Speed 2.60"), or nil.
function G.Speed(link)
	local data = C_TooltipInfo and type(C_TooltipInfo.GetHyperlink) == "function" and select(2, pcall(C_TooltipInfo.GetHyperlink, link)) or nil
	for _, line in ipairs(type(data) == "table" and type(data.lines) == "table" and data.lines or {}) do
		for _, t in ipairs({ line.rightText, line.leftText }) do
			local s = type(t) == "string" and tonumber(t:match("^%a+ (%d+%.%d+)$"))
			if s and s > 0.5 and s < 6 then return s end
		end
	end
	return nil
end

-- The guide's weapon advice, as a lean: "a slower main hand", "a faster off hand" (read from its
-- words). { main = "slow"|"fast"|nil, off = ... }.
function G.SpeedAdvice()
	local g = ns.Guide and ns.Guide.Get()
	local text = g and g.plan and g.plan.weapons
	if type(text) ~= "string" then return {} end
	local low = text:lower()
	local out = {}
	-- The word before the hand: "a slower main hand", "a fast off-hand dagger".
	for _, hand in ipairs({ "main", "off" }) do
		for adj in low:gmatch("(%a+)[%s%-]+" .. hand) do
			if adj:find("slow", 1, true) then out[hand] = "slow" elseif adj:find("fast", 1, true) then out[hand] = "fast" end
		end
	end
	return out
end

-- The lean in weight for a weapon in the main hand (16) or off hand (17): a little for each tenth of
-- a second the guide's way, from 2.0 s (a tie-breaker, not more than its stats).
G.SPEED_LEAN = 2 -- per second
function G.SpeedLean(link, slot)
	if slot ~= 16 and slot ~= 17 then return 0 end
	local want = G.SpeedAdvice()[slot == 16 and "main" or "off"]
	if not want then return 0 end
	local s = G.Speed(link)
	if not s then return 0 end
	return (want == "slow" and (s - 2) or (2 - s)) * G.SPEED_LEAN
end

-- Is link an upgrade for this character? Returns slot, a short reason ("empty slot", "+3 Agi, +4 ilvl").
function G.Upgrade(link)
	local info = Info(link)
	if not info or not G.Usable(link) then return nil end
	local slot = SlotFor(info)
	if not slot or G.COSMETIC[slot] then return nil end
	local worn = Worn(slot)
	if not worn then return slot, "fills an empty slot" end
	if worn.info and worn.info.link and tonumber(link:match("item:(%d+)")) == tonumber(worn.link:match("item:(%d+)")) then return nil end
	local a = G.Weight(link) + G.SpeedLean(link, slot)
	local b = G.Weight(worn.link) + G.SpeedLean(worn.link, slot)
	local dIlvl = (tonumber(info.ilvl) or 0) - (tonumber(worn.info and worn.info.ilvl) or 0)
	if a > b + 0.5 or (a >= b and dIlvl >= 3) then
		local line = ns.Tooltip.Line(link) or ""
		line = line:gsub("^|cff9d7dffSpellmind:|r ", ""):gsub(" vs your .*$", "")
		return slot, line ~= "" and line or ("+" .. dIlvl .. " item level")
	end
	return nil
end

---------------------------------------------------------------------------
-- Quest rewards, cached: a quest's reward choices can only be read while it's the selected one (or
-- its window is open), so they're kept as the player looks at them (SpellmindDB.rewards[id]).
---------------------------------------------------------------------------

local function Cache()
	local db = ns.db
	if not db then return {} end
	if type(db.rewards) ~= "table" then db.rewards = {} end
	return db.rewards
end

-- The links of the selected quest's choices and given items, into the cache.
function G.CacheSelected(id)
	if type(id) ~= "number" or id <= 0 then return end
	local links = {}
	for i = 1, math.min(tonumber((ns.Try(GetNumQuestLogChoices, id))) or 0, 8) do
		local l = ns.Try(GetQuestLogItemLink, "choice", i)
		if type(l) == "string" then links[#links + 1] = l end
	end
	for i = 1, math.min(tonumber((ns.Try(GetNumQuestLogRewards, id))) or 0, 8) do
		local l = ns.Try(GetQuestLogItemLink, "reward", i)
		if type(l) == "string" then links[#links + 1] = l end
	end
	Cache()[id] = links
end

-- Every quest in the log, read without selecting any (C_TooltipInfo.GetQuestLogItem takes the quest's
-- id; probe round 4): its choices and given items, into the cache. Only waiting for the player to
-- open each quest left the Next upgrades empty (seen in game). An item the client hasn't loaded yet
-- is read on a later pass.
function G.ReadLog()
	local TI = rawget(_G, "C_TooltipInfo")
	local QL = C_QuestLog
	if type(TI) ~= "table" or type(TI.GetQuestLogItem) ~= "function" or not QL then return 0 end
	local n, read = tonumber((ns.Try(QL.GetNumQuestLogEntries))) or 0, 0
	for i = 1, n do
		local info = ns.Try(QL.GetInfo, i)
		local id = type(info) == "table" and not info.isHeader and info.questID
		if id and id > 0 then
			local links = {}
			for _, kind in ipairs({ "choice", "reward" }) do
				local count = kind == "choice" and ns.Try(GetNumQuestLogChoices, id) or ns.Try(GetNumQuestLogRewards, id)
				for k = 1, math.min(tonumber(count) or 0, 8) do
					local ok, data = pcall(TI.GetQuestLogItem, kind, k, id)
					if ok and type(data) == "table" then
						local link = type(data.hyperlink) == "string" and data.hyperlink
						if not link and tonumber(data.id) then
							local r = { pcall(C_Item.GetItemInfo, data.id) }
							link = r[1] and r[3] or nil
						end
						if type(link) == "string" then links[#links + 1] = link end
					end
				end
			end
			if #links > 0 then Cache()[id] = links; read = read + 1 end
		end
	end
	return read
end

-- The NPC's window (offering or turning in): its choices' links, into the cache.
function G.CacheWindow()
	local id = tonumber((ns.Try(GetQuestID)))
	if not id or id <= 0 then return end
	local links = {}
	for i = 1, math.min(tonumber((ns.Try(GetNumQuestChoices))) or 0, 8) do
		local l = ns.Try(GetQuestItemLink, "choice", i)
		if type(l) == "string" then links[#links + 1] = l end
	end
	if #links > 0 then Cache()[id] = links end
end

-- Upgrades the character can get now: { slot, link, name, reason, from = "bags" | quest title, quest = id }.
function G.Candidates()
	local out, seen = {}, {}
	local function Add(link, from, quest)
		local id = tonumber(link:match("item:(%d+)"))
		if not id or seen[id] then return end
		local slot, reason = G.Upgrade(link)
		if slot then
			seen[id] = true
			local info = Info(link)
			out[#out + 1] = { slot = slot, link = link, name = info and info.name or "?", q = info and info.q, icon = info and info.icon,
				reason = reason, from = from, quest = quest }
		end
	end
	-- The bags' wearables.
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		for slot = 1, tonumber((ns.Try(C_Container.GetContainerNumSlots, bag))) or 0 do
			local it = ns.Try(C_Container.GetContainerItemInfo, bag, slot)
			if type(it) == "table" and type(it.hyperlink) == "string" then Add(it.hyperlink, "bags") end
		end
	end
	-- The cached rewards of quests still in the log.
	local QL = C_QuestLog
	for id, links in pairs(Cache()) do
		local i = QL and ns.Try(QL.GetLogIndexForQuestID, id)
		if i and i > 0 and type(links) == "table" then
			local title = ns.Try(QL.GetTitleForQuestID, id)
			for _, l in ipairs(links) do Add(l, type(title) == "string" and title or "a quest", id) end
		elseif not i then
			Cache()[id] = nil -- no longer in the log
		end
	end
	return out
end

-- Weak slots, weakest first: { slot, name, why, rank } (empty, well below the level, poor quality).
function G.WeakSlots()
	local out = {}
	local level = Level()
	for slot = 1, 19 do
		if not G.COSMETIC[slot] then
			local worn = Worn(slot)
			if not worn then
				out[#out + 1] = { slot = slot, name = G.SLOT_NAMES[slot], why = "empty", rank = 3 }
			else
				local i = worn.info or {}
				local gap = level - (tonumber(i.ilvl) or level)
				if gap >= G.WEAK_ILVL then
					out[#out + 1] = { slot = slot, name = G.SLOT_NAMES[slot], why = "item level " .. i.ilvl .. ", " .. gap .. " below your level", rank = 2, item = i.name }
				elseif (tonumber(i.q) or 1) <= 1 then
					out[#out + 1] = { slot = slot, name = G.SLOT_NAMES[slot], why = (i.q == 0 and "poor" or "common") .. " quality", rank = 1, item = i.name }
				end
			end
		end
	end
	table.sort(out, function(a, b) if a.rank ~= b.rank then return a.rank > b.rank end return a.slot < b.slot end)
	return out
end

-- The likely pick of a reward choice (the NPC's turn-in window): { i, name, why } or nil.
function G.PickChoice()
	local n = tonumber((ns.Try(GetNumQuestChoices))) or 0
	if n < 2 then return nil end
	local best, bestScore, bestWhy
	for i = 1, n do
		local link = ns.Try(GetQuestItemLink, "choice", i)
		if type(link) == "string" then
			local info = Info(link)
			local slot, reason = G.Upgrade(link)
			local usable = G.Usable(link)
			local score = (usable and 100 or 0) + (slot and 50 or 0) + (G.Weight(link) or 0) + ((info and info.sell or 0) / 10000)
			if not bestScore or score > bestScore then
				best, bestScore = { i = i, name = info and info.name or "?", link = link }, score
				bestWhy = slot and reason or (usable and "usable, the most of your main stats" or "none usable: the best to sell")
			end
		end
	end
	if best then best.why = bestWhy end
	return best
end

-- What's safe to sell (the vendor helper): { name, n, copper, why } and the total, from the bags:
-- grey junk, and bound wearables that can't be used or are worse than what's worn in that slot.
function G.SellList()
	local out, total = {}, 0
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		for slot = 1, tonumber((ns.Try(C_Container.GetContainerNumSlots, bag))) or 0 do
			local it = ns.Try(C_Container.GetContainerItemInfo, bag, slot)
			if type(it) == "table" and type(it.hyperlink) == "string" and not it.hasNoValue then
				local info = Info(it.hyperlink)
				local n = tonumber(it.stackCount) or 1
				local copper = ((info and tonumber(info.sell)) or 0) * n
				local why
				if (it.quality or (info and info.q)) == 0 then why = "grey junk"
				elseif info and ns.Tooltip.SLOTS[info.equipLoc or ""] and it.isBound then
					if not G.Usable(it.hyperlink) then why = "bound, and you can't use it"
					elseif not G.Upgrade(it.hyperlink) then
						local s = SlotFor(info)
						local worn = s and Worn(s)
						if worn and G.Weight(it.hyperlink) < G.Weight(worn.link) then why = "bound, and worse than what you wear" end
					end
				end
				if why and copper > 0 then
					out[#out + 1] = { name = info and info.name or it.itemName or "?", n = n, copper = copper, why = why, q = info and info.q }
					total = total + copper
				end
			end
		end
	end
	table.sort(out, function(a, b) return a.copper > b.copper end)
	return out, total
end

---------------------------------------------------------------------------
-- Events: rewards cached as they're seen
---------------------------------------------------------------------------

-- The log read a few seconds after login (the quest data settles), and again when it changes
-- (throttled), or when the client finishes loading an item it didn't have.
function G.Soon()
	if G.pending then return end
	G.pending = true
	C_Timer.After(2, function() G.pending = nil; pcall(G.ReadLog) end)
end
ns.On("QUEST_LOG_UPDATE", function() G.Soon() end)
ns.On("GET_ITEM_INFO_RECEIVED", function() G.Soon() end)

ns.On("PLAYER_LOGIN", function()
	C_Timer.After(6, function() pcall(G.ReadLog) end)
	if G.hooked or type(rawget(_G, "QuestMapFrame_ShowQuestDetails")) ~= "function" then return end
	hooksecurefunc("QuestMapFrame_ShowQuestDetails", function(id) pcall(G.CacheSelected, id) end)
	G.hooked = true
end)
ns.On("QUEST_DETAIL", function() pcall(G.CacheWindow) end)
ns.On("QUEST_COMPLETE", function() pcall(G.CacheWindow) end)
