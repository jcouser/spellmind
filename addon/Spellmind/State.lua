-- Spellmind: adapted from NeverQuestAlone's addon/NeverQuestAlone/Companion.lua (MIT; see NOTICE.md).
-- State.lua: the character, as ten parts the app keeps (docs/milestone-4.md, "The contract"; focus in
-- docs/milestone-5.md).
--
--   char stats talents spells gear bags skills quests rep focus
--
-- focus is {"v":1} until the player clicks a Spellmind mark: then it's the thing clicked (a quest's
-- text, objectives and rewards), set by Marks.lua through S.SetFocus.
--
-- Each part is a JSON object (v = 1, keys in the contract's order, a key left out when the game
-- has no data for it). A part goes on the strip only when its JSON changed since it was last
-- sent for this character, as a `state` record:
--
--   2 US token US nonce US state US "" US cur=<c>;sid=<16hex>;part=<name>;seq=<n>[;z=1] US body
--
-- body is the JSON, or base64(raw deflate(JSON)) with z=1 when the app's caps list "z". It stays
-- on the strip until the slot's bridge.state.parts[part] >= its seq under the same sid.
--
-- Saved data:
--   SpellmindDB.stateSeq       one per install; only goes up. The parts changed in one build share one.
--   SpellmindDB.chars[k]       per character, k = a hash of UnitGUID("player") (never the name):
--                              { sid, parts = { [part] = { json, seq, z, ok } }, off }
--   SpellmindDB.share          { state = true, identity = false }
--
-- Never read: the character's name, realm and guild (UnitName, GetRealmName, GetGuildInfo), or
-- any other player's. Every client function is called guarded; one that's missing leaves its key out.

local _, ns = ...
local S = {}
ns.State = S
local R = ns.R

S.PARTS = { "char", "stats", "talents", "spells", "gear", "bags", "skills", "quests", "rep", "focus" }
S.MAX_JSON = 8000 -- bytes of one part's JSON
S.MAX_BODY = 2900 -- bytes of one part's body on the strip
S.STR_MAX = 60 -- bytes of one string from the game
local THROTTLE = 2 -- seconds: game events coalesce into one build
local NODES_MAX = 60
local BAG_ITEMS_MAX = 40
local OBJ_MAX = 8 -- objectives per quest
local OFF_WAIT = 60 -- seconds the forget record waits for the app to take it

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- Every return of fn(...), or nothing when fn is missing or raises (ns.Try keeps four).
local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	return (function(ok, ...)
		if ok then return ... end
		return nil
	end)(pcall(fn, ...))
end

local function Whole(v)
	v = tonumber(v)
	if not v or v ~= v then return nil end
	return math.floor(v)
end

local function Round1(v)
	v = tonumber(v)
	if not v or v ~= v then return nil end
	return math.floor(v * 10 + 0.5) / 10
end

---------------------------------------------------------------------------
-- A small JSON writer: objects keep their key order, so the same character always gives the
-- same bytes (the diff against the last sent compares them). Whole numbers print without ".0"
-- on Lua 5.1 (the game) and 5.3 (the test VM).
---------------------------------------------------------------------------

local J = {}
S.JSON = J

-- O("k1", v1, "k2", v2, ...): an object; nil values are left out.
local function O(...)
	local list, n = {}, select("#", ...)
	for i = 1, n, 2 do
		local k, v = select(i, ...)
		list[#list + 1] = { k, v }
	end
	return { _o = list }
end
J.O = O

local function Get(o, k)
	for _, kv in ipairs(o._o) do
		if kv[1] == k then return kv[2] end
	end
end

-- Sets k (added at the end when it isn't there yet).
local function Set(o, k, v)
	for _, kv in ipairs(o._o) do
		if kv[1] == k then
			kv[2] = v
			return
		end
	end
	o._o[#o._o + 1] = { k, v }
end

local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function Str(s)
	local body = tostring(s):gsub('[%c"\\]', function(ch) return ESC[ch] or string.format("\\u%04x", ch:byte()) end)
	return '"' .. body .. '"'
end

local function Num(n)
	if n ~= n or n == math.huge or n == -math.huge then return "0" end
	if n == math.floor(n) and math.abs(n) < 2 ^ 53 then return string.format("%d", n) end
	local s = string.format("%.2f", n):gsub("0+$", ""):gsub("%.$", "")
	return s
end

function J.encode(v)
	local t = type(v)
	if t == "string" then return Str(v) end
	if t == "number" then return Num(v) end
	if t == "boolean" then return v and "true" or "false" end
	if t == "table" then
		local parts = {}
		if v._o then
			for _, kv in ipairs(v._o) do
				if kv[2] ~= nil then parts[#parts + 1] = Str(kv[1]) .. ":" .. J.encode(kv[2]) end
			end
			return "{" .. table.concat(parts, ",") .. "}"
		end
		for i = 1, #v do parts[i] = J.encode(v[i]) end
		return "[" .. table.concat(parts, ",") .. "]"
	end
	return "null"
end

-- From NeverQuestAlone's Chats.lua StripEscapes: colour codes old (|cAARRGGBB) and new (|cnIQ1:),
-- links (keeping their text), textures and atlases.
local function StripEscapes(s)
	if not s:find("|", 1, true) then return s end
	s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
	s = s:gsub("|cn[^:|]*:", "")
	s = s:gsub("|r", "")
	s = s:gsub("|H[^|]*|h([^\r\n]-)|h", "%1")
	s = s:gsub("|T[^|]*|t", "")
	s = s:gsub("|A[^|]*|a", "")
	return s
end

-- Game text as data: escapes and links out (a link's name out of its brackets), then every |
-- and control character; at most 60 bytes (or max), cut at a UTF-8 boundary.
local function Clean(s, max)
	s = tostring(s or "")
	s = StripEscapes((s:gsub("|H([^|]*)|h%[([^\r\n]-)%]|h", "|H%1|h%2|h")))
	s = s:gsub("|", ""):gsub("%c", " "):gsub("%s+", " ")
	return ns.Utf8Cut(ns.Trim(s), max or S.STR_MAX)
end
S.Clean = Clean

-- Clean text, or nil when there's none (the key is left out).
local function Text(s, max)
	if type(s) ~= "string" and type(s) ~= "number" then return nil end
	local c = Clean(s, max)
	if c == "" then return nil end
	return c
end
S.Text = Text
S.Whole = function(v) return Whole(v) end
S.Round1 = function(v) return Round1(v) end

-- The name in an item link: |Hitem:...|h[Name]|h.
local function LinkName(link)
	return type(link) == "string" and link:match("|h%[(.-)%]|h") or nil
end

local function LinkId(link)
	return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

---------------------------------------------------------------------------
-- The parts. Each returns an O object; a part whose client functions are all missing is
-- still {"v":1}.
---------------------------------------------------------------------------

local Build = {}
S.Collect = Build

local function Location()
	local map = ns.Try(C_Map and C_Map.GetBestMapForUnit, "player")
	local x, y
	if type(map) == "number" then
		local pos = ns.Try(C_Map.GetPlayerMapPosition, map, "player")
		local px, py
		if type(pos) == "table" then
			if type(pos.GetXY) == "function" then
				px, py = Call(pos.GetXY, pos)
			else
				px, py = pos.x, pos.y
			end
		end
		if type(px) == "number" and type(py) == "number" and (px > 0 or py > 0) then
			x, y = Round1(px * 100), Round1(py * 100)
		end
	else
		map = nil
	end
	local zone = Text((ns.Try(GetRealZoneText))) or Text((ns.Try(GetZoneText)))
	local sub = Text((ns.Try(GetSubZoneText)))
	if not (map or zone or sub or x) then return nil end
	return O("map", map, "zone", zone, "sub", sub, "x", x, "y", y)
end

function Build.char()
	local class, classFile = ns.Try(UnitClass, "player")
	local race, raceFile = ns.Try(UnitRace, "player")
	local faction = ns.Try(UnitFactionGroup, "player")
	-- Right after PLAYER_LEVEL_UP the unit may still say the old level; the event's is right.
	local level = Whole(ns.Try(UnitLevel, "player"))
	if R.levelUpTo and level and level < R.levelUpTo then level = R.levelUpTo end
	local resting
	if type(IsResting) == "function" then resting = ns.Try(IsResting) and true or false end
	return O("v", 1, "class", Text(class), "classFile", Text(classFile), "race", Text(race), "raceFile", Text(raceFile),
		"faction", Text(faction), "level", level, "xp", Whole(ns.Try(UnitXP, "player")), "xpMax", Whole(ns.Try(UnitXPMax, "player")),
		"rested", Whole(ns.Try(GetXPExhaustion)), "resting", resting, "money", Whole(ns.Try(GetMoney)), "loc", Location())
end

-- The second value (the effective one) of UnitStat, UnitArmor and UnitResistance.
local function Effective(fn, ...)
	local _, eff = ns.Try(fn, ...)
	return Whole(eff)
end

local function AttackPower(fn)
	local base, pos, neg = ns.Try(fn, "player")
	if type(base) ~= "number" then return nil end
	return Whole(base + (tonumber(pos) or 0) + (tonumber(neg) or 0))
end

local RES = { { "fire", 2 }, { "nature", 3 }, { "frost", 4 }, { "shadow", 5 }, { "arcane", 6 } }

function Build.stats()
	local mana = Whole(ns.Try(UnitPowerMax, "player", 0))
	if mana and mana <= 0 then mana = nil end -- a rogue's or a warrior's 0: no mana at all
	local res
	if type(UnitResistance) == "function" then
		res = O()
		for _, r in ipairs(RES) do Set(res, r[1], Effective(UnitResistance, "player", r[2])) end
	end
	return O("v", 1, "hp", Whole(ns.Try(UnitHealthMax, "player")), "mana", mana,
		"str", Effective(UnitStat, "player", 1), "agi", Effective(UnitStat, "player", 2), "sta", Effective(UnitStat, "player", 3),
		"int", Effective(UnitStat, "player", 4), "spi", Effective(UnitStat, "player", 5), "armor", Effective(UnitArmor, "player"),
		"ap", AttackPower(UnitAttackPower), "rap", AttackPower(UnitRangedAttackPower),
		"crit", Round1(ns.Try(GetCritChance)), "rcrit", Round1(ns.Try(GetRangedCritChance)), "scrit", Round1(ns.Try(GetSpellCritChance, 2)),
		"dodge", Round1(ns.Try(GetDodgeChance)), "parry", Round1(ns.Try(GetParryChance)), "block", Round1(ns.Try(GetBlockChance)),
		"res", res)
end

-- A talent's name: the definition's overrideName, else its spell's name.
local function TalentName(config, entryID)
	local CT = C_Traits
	local entry = ns.Try(CT.GetEntryInfo, config, entryID)
	local def = type(entry) == "table" and entry.definitionID or nil
	local info = def and ns.Try(CT.GetDefinitionInfo, def)
	if type(info) ~= "table" then return nil end
	local name = Text(info.overrideName)
	if not name and type(info.spellID) == "number" then
		name = Text((ns.Try(C_Spell and C_Spell.GetSpellName, info.spellID)))
		if not name then
			local sp = ns.Try(C_Spell and C_Spell.GetSpellInfo, info.spellID)
			name = type(sp) == "table" and Text(sp.name) or nil
		end
	end
	return name
end

-- The modern trait tree (Forever has no classic talent functions): one tree per class.
function Build.talents()
	local spec, role
	local SI = C_SpecializationInfo
	local index = type(SI) == "table" and ns.Try(SI.GetSpecialization) or nil
	if type(index) == "number" and index > 0 then
		local _, name, _, _, r = Call(SI.GetSpecializationInfo, index)
		spec, role = Text(name), Text(r)
	end
	local spent, unspent, nodes
	local config = type(C_ClassTalents) == "table" and ns.Try(C_ClassTalents.GetActiveConfigID) or nil
	local CT = C_Traits
	if type(config) == "number" and type(CT) == "table" then
		local info = ns.Try(CT.GetConfigInfo, config)
		local tree = type(info) == "table" and type(info.treeIDs) == "table" and info.treeIDs[1] or nil
		if tree then
			local ids = ns.Try(CT.GetTreeNodes, tree)
			if type(ids) == "table" then
				nodes, spent = {}, 0
				for _, id in ipairs(ids) do
					local node = ns.Try(CT.GetNodeInfo, config, id)
					local r = type(node) == "table" and Whole(node.activeRank) or nil
					if r and r > 0 then
						spent = spent + r
						if #nodes < NODES_MAX then
							-- A choice node: the chosen entry's name.
							local entryID = type(node.activeEntry) == "table" and node.activeEntry.entryID
								or (type(node.entryIDs) == "table" and node.entryIDs[1]) or nil
							nodes[#nodes + 1] = O("id", id, "name", entryID and TalentName(config, entryID) or nil, "r", r, "max", Whole(node.maxRanks))
						end
					end
				end
			end
			local cur = ns.Try(CT.GetTreeCurrencyInfo, config, tree, false)
			local c1 = type(cur) == "table" and cur[1] or nil
			if type(c1) == "table" then
				unspent = Whole(c1.quantity)
				if Whole(c1.spent) then spent = Whole(c1.spent) end
			end
		end
	end
	if unspent == nil then unspent = Whole(ns.Try(GetNumUnspentTalents)) end
	return O("v", 1, "spec", spec, "role", role, "spent", spent, "unspent", unspent, "nodes", nodes)
end

-- Short stat names (NeverQuestAlone's Tooltips.lua STAT_KEYS) for C_Item.GetItemStats's keys,
-- in the order they're written.
local STAT_KEYS = {
	{ "str", { "ITEM_MOD_STRENGTH_SHORT" } },
	{ "agi", { "ITEM_MOD_AGILITY_SHORT" } },
	{ "sta", { "ITEM_MOD_STAMINA_SHORT" } },
	{ "int", { "ITEM_MOD_INTELLECT_SHORT" } },
	{ "spi", { "ITEM_MOD_SPIRIT_SHORT" } },
	{ "armor", { "RESISTANCE0_NAME" } },
	{ "dps", { "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" } },
	{ "ap", { "ITEM_MOD_ATTACK_POWER_SHORT" } },
	{ "rap", { "ITEM_MOD_RANGED_ATTACK_POWER_SHORT" } },
	{ "crit", { "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_CRIT_MELEE_RATING_SHORT", "ITEM_MOD_CRIT_SPELL_RATING_SHORT" } },
	{ "hit", { "ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_HIT_MELEE_RATING_SHORT", "ITEM_MOD_HIT_SPELL_RATING_SHORT" } },
	{ "sp", { "ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT" } },
	{ "heal", { "ITEM_MOD_SPELL_HEALING_DONE_SHORT" } },
	{ "mp5", { "ITEM_MOD_MANA_REGENERATION_SHORT", "ITEM_MOD_POWER_REGEN0_SHORT" } },
	{ "def", { "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT" } },
	{ "dodge", { "ITEM_MOD_DODGE_RATING_SHORT" } },
	{ "parry", { "ITEM_MOD_PARRY_RATING_SHORT" } },
	{ "block", { "ITEM_MOD_BLOCK_RATING_SHORT", "ITEM_MOD_BLOCK_VALUE_SHORT" } },
	{ "fire", { "RESISTANCE2_NAME" } },
	{ "nature", { "RESISTANCE3_NAME" } },
	{ "frost", { "RESISTANCE4_NAME" } },
	{ "shadow", { "RESISTANCE5_NAME" } },
	{ "arcane", { "RESISTANCE6_NAME" } },
}
S.STAT_KEYS = STAT_KEYS

local function ItemStats(link)
	local raw = ns.Try(C_Item and C_Item.GetItemStats, link)
	if type(raw) ~= "table" then return nil end
	local st, n = O(), 0
	for _, sk in ipairs(STAT_KEYS) do
		local sum
		for _, key in ipairs(sk[2]) do
			local v = tonumber(raw[key])
			if v then sum = (sum or 0) + v end
		end
		if sum and sum ~= 0 then
			Set(st, sk[1], Round1(sum))
			n = n + 1
		end
	end
	return n > 0 and st or nil
end
-- An item's stats as the parts have them (an O object, or nil), for focus's reward choices.
S.ItemStatsO = function(link) return ItemStats(link) end
-- An item's stats as a plain table ({ agi = 3, armor = 28 }), for the tooltip line.
function S.ItemStats(link)
	local st = ItemStats(link)
	local out = {}
	for _, kv in ipairs(st and st._o or {}) do out[kv[1]] = kv[2] end
	return out
end

local function ItemLevel(link, fallback)
	local lvl = ns.Try(C_Item and C_Item.GetDetailedItemLevelInfo, link)
	if type(lvl) == "number" and lvl > 0 then return Whole(lvl) end
	if type(fallback) == "number" and fallback > 0 then return Whole(fallback) end
	return nil
end

function Build.gear()
	local items, empty = {}, {}
	if type(GetInventoryItemID) ~= "function" then return O("v", 1) end
	for slot = 1, 19 do
		local id = ns.Try(GetInventoryItemID, "player", slot)
		if type(id) == "number" and id > 0 then
			local link = ns.Try(GetInventoryItemLink, "player", slot)
			local name, _, q, ilvl, _, _, sub = Call(C_Item and C_Item.GetItemInfo, link or id)
			local ench = type(link) == "string" and tonumber(link:match("item:%d+:(%d+)")) or nil
			if ench and ench <= 0 then ench = nil end
			local cur, max = ns.Try(GetInventoryItemDurability, slot)
			local dur
			if type(cur) == "number" and type(max) == "number" and max > 0 then dur = { Whole(cur), Whole(max) } end
			if type(q) ~= "number" and type(link) == "string" then q = tonumber(link:match("|cnIQ(%d)")) end
			items[#items + 1] = O("slot", slot, "id", id, "name", Text(LinkName(link)) or Text(name), "q", Whole(q),
				"ilvl", ItemLevel(link or id, ilvl), "sub", Text(sub), "ench", ench, "st", link and ItemStats(link) or nil, "dur", dur)
		else
			empty[#empty + 1] = slot
		end
	end
	return O("v", 1, "items", items, "empty", empty, "omitted", nil)
end

-- An equip location that means "worn": not empty, not Forever's INVTYPE_NON_EQUIP_IGNORE.
local function Wearable(loc)
	return type(loc) == "string" and loc:match("^INVTYPE_") and not loc:match("^INVTYPE_NON_EQUIP") and true or false
end

local QUEST_CLASS = 12 -- Enum.ItemClass.Questitem

-- Items merged by id and capped at 40: worn items of quality 2 and up first, then quest items,
-- then other quality 2 and up, then the rest, each group in bag order. Junk (quality 0) is only
-- summed.
function Build.bags()
	local CT = C_Container
	if type(CT) ~= "table" then return O("v", 1) end
	local slots, free = 0, 0
	local byId, list = {}, {}
	local junkN, junkCopper = 0, 0
	for bag = 0, tonumber(NUM_BAG_SLOTS) or 4 do
		local n = Whole(ns.Try(CT.GetContainerNumSlots, bag)) or 0
		if n > 0 then
			slots = slots + n
			free = free + (Whole((ns.Try(CT.GetContainerNumFreeSlots, bag))) or 0)
			for slot = 1, n do
				local info = ns.Try(CT.GetContainerItemInfo, bag, slot)
				local id = type(info) == "table" and info.itemID or nil
				if type(id) == "number" then
					local count = Whole(info.stackCount) or 1
					local iname, _, iq, ilvl, _, _, isub, _, loc, _, sell, classID = Call(C_Item and C_Item.GetItemInfo, id)
					local q = Whole(info.quality) or Whole(iq)
					if q == 0 then
						junkN = junkN + count
						if not info.hasNoValue then junkCopper = junkCopper + (Whole(sell) or 0) * count end
					else
						local e = byId[id]
						if not e then
							local wear = Wearable(loc)
							e = { id = id, name = Text(info.itemName) or Text(LinkName(info.hyperlink)) or Text(iname), q = q, n = 0,
								ilvl = wear and ItemLevel(info.hyperlink or id, ilvl) or nil, sub = wear and Text(isub) or nil, equip = wear and loc or nil,
								st = wear and info.hyperlink and ItemStats(info.hyperlink) or nil,
								quest = classID == QUEST_CLASS, at = #list + 1 }
							byId[id] = e
							list[#list + 1] = e
						end
						e.n = e.n + count
						if info.isBound then e.bound = true end
					end
				end
			end
		end
	end
	local function Group(e)
		local good = (e.q or 0) >= 2
		if e.equip and good then return 1 end
		if e.quest then return 2 end
		if good then return 3 end
		return 4
	end
	table.sort(list, function(a, b)
		local ga, gb = Group(a), Group(b)
		if ga ~= gb then return ga < gb end
		return a.at < b.at
	end)
	local items = {}
	for i = 1, math.min(#list, BAG_ITEMS_MAX) do
		local e = list[i]
		-- sub: a wearable item's type ("Bows", "Leather"), so whether the class can use it is in the data.
		items[i] = O("id", e.id, "name", e.name, "q", e.q, "n", e.n, "ilvl", e.ilvl, "sub", e.sub, "equip", e.equip, "st", e.st, "bound", e.bound)
	end
	local more = #list - #items
	return O("v", 1, "slots", slots, "free", free, "items", items,
		"junk", junkN > 0 and O("n", junkN, "copper", junkCopper) or nil, "more", more > 0 and more or nil, "omitted", nil)
end

-- Professions and secondary skills (NeverQuestAlone's Chats.lua PROFESSION_SKILL_IDS, vanilla
-- ids), and weapon skills.
local PROFESSION_SKILL_IDS = {
	[164] = true, [165] = true, [171] = true, [182] = true, [186] = true, [197] = true, [202] = true,
	[333] = true, [393] = true, [129] = true, [185] = true, [356] = true,
}
local WEAPON_SKILL_IDS = {
	[43] = true, [44] = true, [45] = true, [46] = true, [54] = true, [55] = true, [136] = true, [160] = true,
	[162] = true, [172] = true, [173] = true, [176] = true, [226] = true, [228] = true, [229] = true, [473] = true,
}

function Build.skills()
	local SK = C_SkillInfo
	if type(SK) ~= "table" then return O("v", 1) end
	local prof, weapon = {}, {}
	local n = Whole(ns.Try(SK.GetNumSkillLines)) or 0
	local seen = {}
	for i = 1, n do
		local sk = ns.Try(SK.GetSkillLineInfo, i)
		-- Child lines (parentSkillLineID ~= 0) repeat their parent.
		if type(sk) == "table" and not sk.isHeader and (sk.parentSkillLineID or 0) == 0 and type(sk.skillID) == "number" and not seen[sk.skillID] then
			seen[sk.skillID] = true
			local into = (PROFESSION_SKILL_IDS[sk.skillID] and prof) or (WEAPON_SKILL_IDS[sk.skillID] and weapon) or nil
			if into then into[#into + 1] = O("name", Text(sk.name), "rank", Whole(sk.rank), "max", Whole(sk.maxRank)) end
		end
	end
	return O("v", 1, "prof", prof, "weapon", weapon)
end

-- From NeverQuestAlone's Store.lua QuestLogMax: the larger of the API's cap and Forever's own
-- constant, else 40; never fewer than the log holds.
local function QuestMax(atLeast)
	local api = Whole(ns.Try(C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept))
	local qc = type(Constants) == "table" and type(Constants.QuestLogConsts) == "table" and Constants.QuestLogConsts or nil
	local const = qc and Whole(qc.MAXIMUM_NUM_QUESTS_LOG_CAN_ACCEPT) or nil
	local max = 40
	if api and api >= 1 and (not const or api >= const) then max = api elseif const and const >= 1 then max = const end
	return math.max(max, atLeast)
end

local function Objectives(id)
	local out = {}
	for _, o in ipairs(ns.Try(C_QuestLog.GetQuestObjectives, id) or {}) do
		if #out >= OBJ_MAX then break end
		if type(o) == "table" then
			-- The client puts the count in the text too ("Prairie Wolf Paw: 3/6"); have and need carry it.
			local text = tostring(o.text or ""):gsub("^%s*%d+%s*/%s*%d+%s*", ""):gsub("%s*:?%s*%d+%s*/%s*%d+%s*$", "")
			out[#out + 1] = O("text", Text(text), "have", Whole(o.numFulfilled) or 0, "need", Whole(o.numRequired) or 0)
		end
	end
	return #out > 0 and out or nil
end
S.Objectives = Objectives

-- From NeverQuestAlone's Store.lua ns.QuestLog: one pass over every row C_QuestLog.GetInfo lists,
-- quests under a collapsed header too (Forever lists them), so no header is ever opened or
-- closed. Headers, hidden rows and tasks aren't quests; a row with no quest id yet is counted
-- in unread.
function Build.quests()
	local QL = C_QuestLog
	if type(QL) ~= "table" then return O("v", 1, "omitted", {}) end
	local function Complete(id)
		local c = ns.Try(QL.IsComplete, id)
		if c == nil then c = ns.Try(QL.ReadyForTurnIn, id) end
		return c and true or false
	end
	local n = ns.Try(QL.GetNumQuestLogEntries)
	local list, unread = {}, 0
	for i = 1, Whole(n) or 0 do
		local info = ns.Try(QL.GetInfo, i)
		if type(info) == "table" and not info.isHeader and not info.isHidden and not info.isTask
			and (not info.isBounty or Complete(info.questID)) then
			local id = info.questID
			if type(id) == "number" and id > 0 then
				local done = Complete(id)
				list[#list + 1] = O("id", id, "title", Text(info.title), "level", Whole(info.level), "complete", done, "obj", Objectives(id))
			else
				unread = unread + 1
			end
		end
	end
	return O("v", 1, "count", #list, "max", QuestMax(#list), "unread", unread, "list", list, "omitted", {})
end

-- focus: what the player clicked Explain on (Marks.lua), or {"v":1}. Kept until the next click; the
-- app gives it only to the messages whose about= names it.
function Build.focus()
	return R.focus or O("v", 1)
end

-- Marks.lua: the thing clicked (an O object with v = 1), or nil to empty it.
function S.SetFocus(obj)
	R.focus = obj
end

-- Factions in the game's order; headers are counted only when collapsed (a header with its own
-- standing is a faction too). v and max are the standing within the current reaction.
-- spells: the spellbook's tabs (C_SpellBook, probed 2026-11-10: the classic GetSpellTabInfo and
-- GetNumSpellTabs are gone). Each known spell with its rank ("Rank 2" → 2) and passives marked; the
-- spells the book shows as coming later ("future" entries) with the level they're learned at, soonest
-- first. A player asked for it: talents alone don't say what a character can cast.
local SPELL_TABS_MAX, SPELLS_MAX, NEXT_MAX = 8, 100, 10
function Build.spells()
	local SB = C_SpellBook
	if type(SB) ~= "table" then return O("v", 1) end
	local E = type(Enum) == "table" and Enum or {}
	local bank = (E.SpellBookSpellBank and E.SpellBookSpellBank.Player) or 0
	local SPELL = (E.SpellBookItemType and E.SpellBookItemType.Spell) or 1
	local FUTURE = (E.SpellBookItemType and E.SpellBookItemType.FutureSpell) or 2
	local tabs, coming, total = {}, {}, 0
	for line = 1, Whole(ns.Try(SB.GetNumSpellBookSkillLines)) or 0 do
		local info = ns.Try(SB.GetSpellBookSkillLineInfo, line)
		if type(info) == "table" and not info.shouldHide and not info.isGuild and #tabs < SPELL_TABS_MAX then
			local list = {}
			local off, n = Whole(info.itemIndexOffset) or 0, Whole(info.numSpellBookItems) or 0
			for i = off + 1, off + n do
				local it = ns.Try(SB.GetSpellBookItemInfo, i, bank)
				if type(it) == "table" and type(it.name) == "string" and it.name ~= "" then
					local rank = type(it.subName) == "string" and Whole(it.subName:match("(%d+)")) or nil
					if it.itemType == FUTURE then
						local lvl = Whole(ns.Try(SB.GetSpellBookItemLevelLearned, i, bank))
						coming[#coming + 1] = { lvl or 999, #coming, O("name", Text(it.name), "rank", rank, "level", lvl) }
					elseif it.itemType == SPELL and total < SPELLS_MAX then
						total = total + 1
						list[#list + 1] = O("name", Text(it.name), "rank", rank, "passive", it.isPassive and true or nil)
					end
				end
			end
			if #list > 0 then tabs[#tabs + 1] = O("name", Text(info.name), "list", list) end
		end
	end
	table.sort(coming, function(a, b) if a[1] ~= b[1] then return a[1] < b[1] end return a[2] < b[2] end)
	local nextList = {}
	for i = 1, math.min(#coming, NEXT_MAX) do nextList[i] = coming[i][3] end
	return O("v", 1, "tabs", tabs, "next", #nextList > 0 and nextList or nil)
end

function Build.rep()
	local RP = C_Reputation
	if type(RP) ~= "table" then return O("v", 1) end
	local watchedId
	local w = ns.Try(RP.GetWatchedFactionData)
	if type(w) == "table" then watchedId = w.factionID end
	local list, collapsed = {}, 0
	for i = 1, Whole(ns.Try(RP.GetNumFactions)) or 0 do
		local f = ns.Try(RP.GetFactionDataByIndex, i)
		if type(f) == "table" then
			if f.isHeader and f.isCollapsed then collapsed = collapsed + 1 end
			if (not f.isHeader or f.isHeaderWithRep) and type(f.factionID) == "number" and f.factionID > 0 then
				local cur, lo, hi = tonumber(f.currentStanding), tonumber(f.currentReactionThreshold), tonumber(f.nextReactionThreshold)
				local v = (cur and lo) and Whole(cur - lo) or Whole(cur)
				local max = (hi and lo) and Whole(hi - lo) or nil
				local watched = (f.isWatched or (watchedId ~= nil and watchedId == f.factionID)) and true or nil
				list[#list + 1] = O("id", f.factionID, "name", Text(f.name), "r", Whole(f.reaction), "v", v, "max", max, "watched", watched)
			end
		end
	end
	return O("v", 1, "list", list, "collapsed", collapsed)
end

---------------------------------------------------------------------------
-- Deflate (NeverQuestAlone's Transport.lua T.Deflate): Enum.CompressionMethod.Deflate (0) is raw
-- deflate, what Node's zlib.inflateRawSync reads. nil, and the body goes as JSON, when an API is
-- missing or fails, when the result is no shorter, or when the client's own inflate (if it has
-- one) doesn't give back the exact text.
---------------------------------------------------------------------------

function S.Deflate(text)
	local E = C_EncodingUtil
	if type(text) ~= "string" or type(E) ~= "table" or type(E.CompressString) ~= "function" or type(E.EncodeBase64) ~= "function" then
		return nil
	end
	local method = (type(Enum) == "table" and Enum.CompressionMethod and Enum.CompressionMethod.Deflate) or 0
	local ok, packed = pcall(E.CompressString, text, method)
	if not ok or type(packed) ~= "string" or packed == "" then return nil end
	local b64
	ok, b64 = pcall(E.EncodeBase64, packed)
	if not ok or type(b64) ~= "string" then return nil end
	b64 = b64:gsub("%s+", "")
	if b64 == "" or #b64 >= #text or b64:find("[^%w%+/=]") then return nil end
	if type(E.DecodeBase64) == "function" and type(E.DecompressString) == "function" then
		local raw, back
		ok, raw = pcall(E.DecodeBase64, b64)
		if not ok or type(raw) ~= "string" then return nil end
		ok, back = pcall(E.DecompressString, raw, method)
		if not ok or back ~= text then return nil end
	end
	return b64
end

---------------------------------------------------------------------------
-- Fitting a part: at most 8,000 bytes of JSON and 2,900 on the strip. Over either, the part's
-- own trims run in order, each named in its omitted; the last resort is too_large.
---------------------------------------------------------------------------

local function Omit(obj, name)
	local om = Get(obj, "omitted")
	if type(om) ~= "table" or om._o then om = {} end
	for _, x in ipairs(om) do if x == name then return end end
	om[#om + 1] = name
	Set(obj, "omitted", om)
end

-- Each trim: { name, fn(obj) -> true while it can cut more (called again until the part fits) }.
local TRIMS = {
	quests = {
		{ "obj.text", function(obj)
			for _, q in ipairs(Get(obj, "list") or {}) do
				for _, o in ipairs(Get(q, "obj") or {}) do Set(o, "text", nil) end
			end
		end },
		{ "obj", function(obj)
			for _, q in ipairs(Get(obj, "list") or {}) do Set(q, "obj", nil) end
		end },
	},
	bags = {
		{ "items", function(obj)
			local items = Get(obj, "items")
			if type(items) ~= "table" or #items == 0 then return false end
			items[#items] = nil
			Set(obj, "more", (Get(obj, "more") or 0) + 1)
			return #items > 0
		end },
	},
	gear = {
		{ "st", function(obj)
			for _, it in ipairs(Get(obj, "items") or {}) do Set(it, "st", nil) end
		end },
	},
	focus = {
		{ "text", function(obj)
			local t = Get(obj, "text")
			if type(t) ~= "string" or #t <= 200 then Set(obj, "text", nil); return false end
			Set(obj, "text", ns.Utf8Cut(t, math.floor(#t / 2)))
			return true
		end },
		{ "rewards", function(obj) Set(obj, "choices", nil); Set(obj, "items", nil) end },
	},
	spells = {
		{ "next", function(obj) Set(obj, "next", nil) end },
		{ "passive", function(obj)
			for _, tab in ipairs(Get(obj, "tabs") or {}) do
				local list, keep = Get(tab, "list") or {}, {}
				for _, s in ipairs(list) do if not Get(s, "passive") then keep[#keep + 1] = s end end
				Set(tab, "list", keep)
			end
		end },
	},
}

-- json, body, deflated when it fits; json alone when it doesn't.
local function Encode(obj, z)
	local json = J.encode(obj)
	if #json > S.MAX_JSON then return json end
	local body, deflated = json, false
	if z then
		local b = S.Deflate(json)
		if b then body, deflated = b, true end
	end
	if #body > S.MAX_BODY then return json end
	return json, body, deflated
end

function S.Fit(name, obj, z)
	local json, body, deflated = Encode(obj, z)
	if body then return json, body, deflated end
	for _, trim in ipairs(TRIMS[name] or {}) do
		Omit(obj, trim[1])
		repeat
			local more = trim[2](obj)
			json, body, deflated = Encode(obj, z)
			if body then return json, body, deflated end
		until not more
	end
	json = J.encode(O("v", 1, "too_large", true))
	return json, json, false
end

-- One part as it goes: its JSON, its body and whether that's deflated.
function S.Part(name, z)
	local fn = Build[name]
	if not fn then return nil end
	return S.Fit(name, fn(), z)
end

---------------------------------------------------------------------------
-- The character's saved state, sid and seq
---------------------------------------------------------------------------

-- A 31-bit hash as 8 hex, in doubles: the same on Lua 5.1 (the game) and the test VM (whose
-- integers are 32-bit).
local function Hash(s)
	local h = 5381.0
	for i = 1, #s do h = (h * 33.0 + s:byte(i)) % 2147483647.0 end
	return string.format("%08x", math.floor(h))
end

-- The saved data's key for this character: a hash of its GUID, never its name.
function S.Key()
	local guid = ns.Try(UnitGUID, "player")
	if type(guid) ~= "string" or guid == "" then return "player" end
	return "g" .. Hash(guid)
end

function S.NewSid()
	return string.format("%04x%04x%04x%04x", math.random(0, 0xFFFF), math.random(0, 0xFFFF), math.random(0, 0xFFFF), math.random(0, 0xFFFF))
end

-- This character's entry, made when it isn't there.
function S.Me()
	local db = ns.db
	local key = S.Key()
	local me = db.chars[key]
	if type(me) ~= "table" then
		me = { parts = {} }
		db.chars[key] = me
	end
	if type(me.parts) ~= "table" then me.parts = {} end
	if type(me.sid) ~= "string" or not me.sid:match("^%x+$") or #me.sid ~= 16 then
		me.sid = S.NewSid()
		me.parts = {}
	end
	return me
end

function S.Sid()
	if not ns.db then return nil end
	return S.Me().sid
end

-- PLAYER_ENTERING_WORLD: a login (or a crash's next one) draws a new sid, so the app starts this
-- character over and every part goes again; a /reload or a loading screen keeps it.
function S.OnEnteringWorld(isInitialLogin)
	if not ns.db then return end
	local me = S.Me()
	if isInitialLogin then
		me.sid = S.NewSid()
		me.parts = {}
		R.stateBody = {}
	end
	S.Dirty()
end

---------------------------------------------------------------------------
-- Builds
---------------------------------------------------------------------------

function S.Sharing()
	return ns.db ~= nil and ns.db.share.state ~= false
end

-- Parts go only to an app whose caps list "state", while sharing is on.
function S.Active()
	return S.Sharing() and R.caps ~= nil and R.caps.state == true
end

-- Every part read now; the ones whose JSON changed get one new seq. noDraw: the caller draws
-- (a send, so the message and its parts come out in one frame). Returns how many changed.
function S.Build(noDraw)
	if not S.Active() then return 0 end
	R.stateDirty = nil
	R.stateBuilt = true
	R.stateCombat = nil
	R.stateErr = {}
	R.stateBody = R.stateBody or {}
	local me = S.Me()
	local z = R.caps.z == true
	local changed = {}
	for _, p in ipairs(S.PARTS) do
		local ok, json, body, deflated = pcall(S.Part, p, z)
		if not ok then
			R.stateErr[p] = tostring(json)
		elseif json then
			local rec = me.parts[p]
			if type(rec) ~= "table" or rec.json ~= json then changed[#changed + 1] = { p, json, body, deflated } end
		end
	end
	if #changed == 0 then return 0 end
	local db = ns.db
	db.stateSeq = math.floor(db.stateSeq) + 1
	for _, c in ipairs(changed) do
		me.parts[c[1]] = { json = c[2], seq = db.stateSeq, z = c[4] or nil, ok = false }
		R.stateBody[c[1]] = { seq = db.stateSeq, body = c[3] }
	end
	if not noDraw then ns.Link.RefreshStrip() end
	return #changed
end

-- A game event: one build THROTTLE seconds later, however many come; none in combat (it waits
-- for PLAYER_REGEN_ENABLED, or the next send).
function S.Dirty()
	R.stateDirty = true
	if R.stateTimer then return end
	R.stateTimer = true
	C_Timer.After(THROTTLE, function()
		R.stateTimer = nil
		if not R.stateDirty then return end
		if type(InCombatLockdown) == "function" and InCombatLockdown() then
			R.stateCombat = true
			return
		end
		S.Build()
	end)
end

function S.OnCombatEnd()
	if R.stateCombat and R.stateDirty then S.Build() end
end

-- C.Send, before the message's record: the state built, then st= for the message, the parts the
-- app hasn't confirmed as part:seq (empty: it has them all), or nil (no game data: sharing is off
-- or the app doesn't take it).
function S.BeforeSend()
	if not S.Active() then return nil end
	S.Build(true)
	local me = S.Me()
	local out = {}
	for _, p in ipairs(S.PARTS) do
		local rec = me.parts[p]
		if type(rec) == "table" and not rec.ok then out[#out + 1] = p .. ":" .. ns.Int(rec.seq) end
	end
	return table.concat(out, ",")
end

---------------------------------------------------------------------------
-- The strip and the slot
---------------------------------------------------------------------------

-- A part's body: the build's, or the saved JSON again (deflated as it was).
local function Body(p, rec)
	local c = R.stateBody and R.stateBody[p]
	if c and c.seq == rec.seq then return c.body end
	local body = rec.json
	if rec.z then body = S.Deflate(rec.json) end
	if type(body) ~= "string" or #body > S.MAX_BODY then return nil end
	R.stateBody = R.stateBody or {}
	R.stateBody[p] = { seq = rec.seq, body = body }
	return body
end

-- The state records to draw, after the keyed records (Link.StripEntries): the forget record,
-- then each part the app hasn't confirmed, in part order. Only once the app has answered this
-- session's hello and lists "state" in its caps.
function S.Entries()
	local out = {}
	if not ns.db or not R.nonce or not R.helloAnswered or not (R.caps and R.caps.state) then return out end
	local db, me = ns.db, S.Me()
	if me.off then
		R.offDrawnAt = R.offDrawnAt or GetTime()
		if GetTime() - R.offDrawnAt < OFF_WAIT then
			out[#out + 1] = { state = true, waits = true, wire = ns.Link.Record(R.nonce, "state", "",
				{ { "cur", db.cursor }, { "sid", me.sid }, { "part", "all" }, { "seq", me.off }, { "off", 1 } }, "") }
		else
			me.off = nil
		end
	end
	if not S.Sharing() then return out end
	for _, p in ipairs(S.PARTS) do
		local rec = me.parts[p]
		if type(rec) == "table" and not rec.ok and type(rec.json) == "string" then
			local body = Body(p, rec)
			if body then
				local args = { { "cur", db.cursor }, { "sid", me.sid }, { "part", p }, { "seq", rec.seq } }
				if rec.z then args[#args + 1] = { "z", 1 } end
				out[#out + 1] = { state = true, waits = true, part = p, wire = ns.Link.Record(R.nonce, "state", "", args, body) }
			end
		end
	end
	return out
end

local function Has(parts, p, seq)
	return type(parts) == "table" and (tonumber(parts[p]) or -1) >= seq
end

-- Every slot for our token (Link.HandleSlotData): its caps, and bridge.state = { sid, parts =
-- { [part] = seq } } for the token's current sid. A part is off the strip once the app has its
-- seq under our sid. Once per hello (the first slot that answers it), every part the app doesn't
-- have goes again, so an app that lost them gets the full set.
function S.OnBridge(bridge)
	if not ns.db or type(bridge) ~= "table" then return end
	-- What the app's AI offers the chat window's header (milestone 6): its name, model, thinking levels, search.
	local ai = type(bridge.ai) == "table" and bridge.ai or nil
	if ai ~= R.ai then
		R.ai = ai
		if ns.Window then ns.Window.Refresh() end
	end
	local caps = {}
	for _, c in ipairs(type(bridge.caps) == "table" and bridge.caps or {}) do
		if type(c) == "string" then caps[c] = true end
	end
	R.caps = caps
	local me = S.Me()
	local st = type(bridge.state) == "table" and bridge.state or nil
	local parts = st and st.sid == me.sid and type(st.parts) == "table" and st.parts or nil
	-- The forget record is taken once the app holds no part older than it.
	if me.off and R.helloAnswered and R.offDrawnAt then
		local left = false
		for _, v in pairs(parts or {}) do
			if (tonumber(v) or 0) <= me.off then left = true end
		end
		if not left then me.off, R.offDrawnAt = nil, nil end
	end
	if caps.state and S.Sharing() then
		-- A deflated part waiting for an app that no longer takes z is built again as JSON.
		if not caps.z then
			for _, rec in pairs(me.parts) do
				if type(rec) == "table" and rec.z and not rec.ok then rec.json, R.stateDirty = nil, true end
			end
		end
		if not R.stateBuilt or R.stateDirty then S.Build(true) end
		local answered = R.helloAnswered and R.stateHello ~= R.nonce
		if answered then R.stateHello = R.nonce end
		for p, rec in pairs(me.parts) do
			if type(rec) == "table" and type(rec.seq) == "number" then
				if answered then
					rec.ok = Has(parts, p, rec.seq)
				elseif not rec.ok and Has(parts, p, rec.seq) then
					rec.ok = true
				end
			end
		end
	end
	ns.Link.RefreshStrip()
end

---------------------------------------------------------------------------
-- /sm data
---------------------------------------------------------------------------

-- /sm data off: the app forgets this character (part=all;off=1) and nothing more is sent.
function S.Off()
	local db, me = ns.db, S.Me()
	db.share.state = false
	db.stateSeq = math.floor(db.stateSeq) + 1
	me.off = db.stateSeq
	me.parts = {}
	R.stateBody, R.offDrawnAt = {}, nil
	ns.Link.RefreshStrip()
end

-- /sm data on: sending again, every part with a new seq.
function S.On()
	local db = ns.db
	db.share.state = true
	S.Me().parts = {}
	R.stateBody = {}
	S.Build()
	ns.Link.RefreshStrip()
end

local function Bytes(n)
	n = math.floor(n)
	if n >= 1000 then return string.format("%d,%03d", math.floor(n / 1000), n % 1000) end
	return tostring(n)
end

-- What /sm data shows: each part's size and whether the app has it.
function S.Report()
	local lines = {}
	if not ns.db then return lines end
	if not S.Sharing() then
		lines[1] = "Game data is off: the app gets none of your character. Type /sm data on to send it again."
		return lines
	end
	if not R.caps then
		lines[1] = "Game data: the Spellmind app hasn't been heard from yet this session, so nothing has been sent."
		return lines
	end
	if not R.caps.state then
		lines[1] = "Game data: this Spellmind app doesn't take your character's data. Update the app."
		return lines
	end
	S.Build()
	local me = S.Me()
	lines[1] = "Game data the app gets (your name, realm and guild never leave the game):"
	for _, p in ipairs(S.PARTS) do
		local rec = me.parts[p]
		local line
		if type(rec) ~= "table" or type(rec.json) ~= "string" then
			line = p .. ": not read" .. (R.stateErr and R.stateErr[p] and " (the game didn't answer)" or "")
		else
			line = p .. ": " .. Bytes(#rec.json) .. " bytes"
			local body = rec.z and Body(p, rec)
			if body then line = line .. " (" .. Bytes(#body) .. " compressed)" end
			line = line .. (rec.ok and ", the app has it" or ", on its way")
		end
		lines[#lines + 1] = line
	end
	lines[#lines + 1] = "Type /sm data off to stop sending it."
	return lines
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

ns.On("PLAYER_ENTERING_WORLD", function(_, isInitialLogin) S.OnEnteringWorld(isInitialLogin) end)
ns.On("PLAYER_LEVEL_UP", function(_, level)
	R.levelUpTo = tonumber(level)
	S.Dirty()
end)
ns.On("UNIT_INVENTORY_CHANGED", function(_, unit)
	if unit == nil or unit == "player" then S.Dirty() end
end)
for _, ev in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "QUEST_LOG_UPDATE", "SKILL_LINES_CHANGED",
	"UPDATE_FACTION", "TRAIT_CONFIG_UPDATED", "PLAYER_XP_UPDATE", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA",
	"ZONE_CHANGED_INDOORS", "PLAYER_MONEY", "PLAYER_UPDATE_RESTING", "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE" }) do
	ns.On(ev, function() S.Dirty() end)
end
ns.On("PLAYER_REGEN_ENABLED", S.OnCombatEnd)
