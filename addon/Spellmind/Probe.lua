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
	ns.db.probe = out
	local n = 0
	for _ in pairs(out) do n = n + 1 end
	return n
end
