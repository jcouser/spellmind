-- Spellmind's API probe (milestone 4's research, docs/milestone-4.md §1): /sm probe calls every client
-- function the character collectors might use, safely (pcall), and saves what each returned into
-- SpellmindDB.probe, read from WTF\Account\...\SavedVariables\Spellmind.lua after a /reload.
-- Nothing leaves the game; your character's name, realm and guild aren't read.
local addonName, ns = ...
local unpack = unpack or table.unpack -- Lua 5.1 in game; 5.3 in the tests' VM

local function describe(v, depth)
	local t = type(v)
	if t == "table" then
		if (depth or 0) >= 2 then return "table" end
		local out, n = {}, 0
		for k, x in pairs(v) do
			n = n + 1
			if n > 24 then out["..."] = "more"; break end
			out[tostring(k)] = describe(x, (depth or 0) + 1)
		end
		return out
	elseif t == "string" then
		return "string:" .. v:sub(1, 60):gsub("|", "||")
	elseif t == "function" then
		return "function"
	end
	return t .. ":" .. tostring(v)
end

local function try(fn, ...)
	if type(fn) ~= "function" then return { missing = true } end
	local r = { pcall(fn, ...) }
	if not r[1] then return { error = tostring(r[2]):sub(1, 120) } end
	local out = { n = #r - 1 }
	for i = 2, math.min(#r, 16) do out[i - 1] = describe(r[i]) end
	return out
end

local function g(path)
	local v = _G
	for part in path:gmatch("[^%.]+") do
		if type(v) ~= "table" then return nil end
		v = v[part]
	end
	return v
end

function ns.Probe()
	local link5 = GetInventoryItemLink and GetInventoryItemLink("player", 5)
	local link16 = GetInventoryItemLink and GetInventoryItemLink("player", 16)
	local calls = {
		{ "GetBuildInfo" },
		{ "UnitClass", "player" }, { "UnitRace", "player" }, { "UnitFactionGroup", "player" }, { "UnitLevel", "player" },
		{ "UnitXP", "player" }, { "UnitXPMax", "player" }, { "GetXPExhaustion" }, { "IsResting" }, { "GetMoney" },
		{ "C_Map.GetBestMapForUnit", "player" }, { "GetRealZoneText" }, { "GetSubZoneText" },
		{ "UnitStat", "player", 1 }, { "UnitStat", "player", 2 }, { "UnitArmor", "player" }, { "UnitHealthMax", "player" },
		{ "UnitPowerMax", "player", 0 }, { "UnitAttackPower", "player" }, { "UnitRangedAttackPower", "player" },
		{ "GetCritChance" }, { "GetRangedCritChance" }, { "GetSpellCritChance", 2 }, { "GetDodgeChance" }, { "GetParryChance" },
		{ "GetBlockChance" }, { "UnitResistance", "player", 2 },
		{ "GetNumTalentTabs" }, { "GetTalentTabInfo", 1 }, { "GetNumTalents", 1 }, { "GetTalentInfo", 1, 1 }, { "UnitCharacterPoints", "player" },
		{ "C_SpecializationInfo.GetSpecialization" }, { "GetSpecialization" },
		{ "GetInventoryItemID", "player", 5 }, { "GetInventoryItemDurability", 5 },
		{ "C_Item.GetItemInfo", link16 or link5 or 6948 }, { "C_Item.GetDetailedItemLevelInfo", link5 or 6948 },
		{ "C_Item.GetItemStats", link5 or "item:6948" }, { "GetItemStats", link5 or "item:6948" },
		{ "C_Container.GetContainerNumSlots", 0 }, { "C_Container.GetContainerNumFreeSlots", 0 }, { "C_Container.GetContainerItemInfo", 0, 1 },
		{ "C_SkillInfo.GetNumSkillLines" }, { "C_SkillInfo.GetSkillLineInfo", 1 }, { "GetNumSkillLines" }, { "GetSkillLineInfo", 1 },
		{ "C_Reputation.GetNumFactions" }, { "C_Reputation.GetFactionDataByIndex", 1 }, { "GetNumFactions" }, { "GetFactionInfo", 1 },
		{ "C_Reputation.GetWatchedFactionData" }, { "GetWatchedFactionInfo" },
		{ "C_QuestLog.GetNumQuestLogEntries" }, { "C_QuestLog.GetInfo", 1 },
		{ "C_EncodingUtil.CompressString", "spellmind probe" }, { "C_EncodingUtil.EncodeBase64", "spellmind" },
	}
	local out = { at = time and time() or 0 }
	for _, c in ipairs(calls) do
		local name = c[1]
		out[name .. (c[2] ~= nil and ("(" .. tostring(c[2]) .. (c[3] ~= nil and ("," .. tostring(c[3])) or "") .. ")") or "()")] = try(g(name), select(2, unpack(c)))
	end
	out.NUM_BAG_SLOTS = describe(NUM_BAG_SLOTS)
	-- Talents (round 2): the classic talent functions are gone on Forever, so list what the client has.
	-- Every global function, and every C_ namespace's functions, whose name says talent, spec or trait.
	local found, n = {}, 0
	for name, v in pairs(_G) do
		if type(name) == "string" then
			local lower = name:lower()
			if type(v) == "function" and (lower:find("talent") or lower:find("speciali") or lower:find("trait")) then
				n = n + 1
				if n <= 80 then found[name] = "function" end
			elseif type(v) == "table" and name:sub(1, 2) == "C_" and (lower:find("talent") or lower:find("spec") or lower:find("trait")) then
				local fns = {}
				for k, f in pairs(v) do if type(f) == "function" then fns[#fns + 1] = k end end
				table.sort(fns)
				found[name] = table.concat(fns, ",")
			end
		end
	end
	out.talentApi = found
	-- And the likely ones, called: the spec's info, the active talent config, and its tree's nodes.
	local spec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization and C_SpecializationInfo.GetSpecialization()
	out["C_SpecializationInfo.GetSpecializationInfo(spec)"] = try(g("C_SpecializationInfo.GetSpecializationInfo"), spec or 1)
	out["GetSpecializationInfo(spec)"] = try(g("GetSpecializationInfo"), spec or 1)
	local config = C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
	out["C_ClassTalents.GetActiveConfigID()"] = describe(config)
	if config and C_Traits then
		out["C_Traits.GetConfigInfo(config)"] = try(C_Traits.GetConfigInfo, config)
		local info = C_Traits.GetConfigInfo and C_Traits.GetConfigInfo(config)
		local tree = info and info.treeIDs and info.treeIDs[1]
		if tree and C_Traits.GetTreeNodes then
			local nodes = C_Traits.GetTreeNodes(tree) or {}
			out["C_Traits.GetTreeNodes(tree)#"] = #nodes
			if nodes[1] then out["C_Traits.GetNodeInfo(config,node1)"] = try(C_Traits.GetNodeInfo, config, nodes[1]) end
		end
	end
	out["C_Talent?"] = describe(rawget(_G, "C_Talent") ~= nil)
	-- The spellbook (round 3): the C_SpellBook namespace's functions, its skill lines (tabs), and the
	-- first few spells of the class's tab with their rank text.
	local sb = rawget(_G, "C_SpellBook")
	if type(sb) == "table" then
		local fns = {}
		for k, f in pairs(sb) do if type(f) == "function" then fns[#fns + 1] = k end end
		table.sort(fns)
		out["C_SpellBook"] = table.concat(fns, ",")
		out["C_SpellBook.GetNumSpellBookSkillLines()"] = try(sb.GetNumSpellBookSkillLines)
		for line = 1, 3 do out["C_SpellBook.GetSpellBookSkillLineInfo(" .. line .. ")"] = try(sb.GetSpellBookSkillLineInfo, line) end
		local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
		out["Enum.SpellBookSpellBank.Player"] = describe(bank)
		local info2 = sb.GetSpellBookSkillLineInfo and select(2, pcall(sb.GetSpellBookSkillLineInfo, 2))
		local first = type(info2) == "table" and (info2.itemIndexOffset or 0) + 1 or 1
		for i = first, first + 3 do
			out["C_SpellBook.GetSpellBookItemInfo(" .. i .. ")"] = try(sb.GetSpellBookItemInfo, i, bank)
			out["C_SpellBook.GetSpellBookItemName(" .. i .. ")"] = try(sb.GetSpellBookItemName, i, bank)
		end
	else
		out["C_SpellBook"] = "missing"
	end
	out["GetNumSpellTabs()"] = try(g("GetNumSpellTabs"))
	out["GetSpellTabInfo(2)"] = try(g("GetSpellTabInfo"), 2)
	out["GetSpellBookItemName(1,spell)"] = try(g("GetSpellBookItemName"), 1, "spell")
	out["C_Spell.GetSpellSubtext(1752)"] = try(g("C_Spell.GetSpellSubtext"), 1752) -- Sinister Strike (rank 1)
	out["C_Spell.GetSpellName(1752)"] = try(g("C_Spell.GetSpellName"), 1752)
	out["IsPlayerSpell(1752)"] = try(g("IsPlayerSpell"), 1752)
	ns.db.probe = out
	local n = 0
	for _ in pairs(out) do n = n + 1 end
	return n
end
