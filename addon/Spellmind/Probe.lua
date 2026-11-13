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

local function fnList(ns_, cap)
	if type(ns_) ~= "table" then return "missing" end
	local fns = {}
	for k, f in pairs(ns_) do if type(f) == "function" then fns[#fns + 1] = k end end
	table.sort(fns)
	if #fns > (cap or 200) then for i = #fns, (cap or 200) + 1, -1 do fns[i] = nil end; fns[#fns + 1] = "..." end
	return table.concat(fns, ",")
end

-- Round 4 (docs/features.md §5): quest help and the marks in the game's own windows. Read only: it
-- doesn't select a quest, open a window or set a waypoint. Other addons are listed by folder name.
function ns.ProbeRound4(out, try, g)
	-- The quest APIs: what the client has in each namespace, then the likely calls on the first quest.
	for _, name in ipairs({ "C_QuestLog", "C_SuperTrack", "C_TaskQuest", "C_QuestInfoSystem", "C_Map", "C_TradeSkillUI", "C_AddOns", "C_TooltipInfo", "C_CombatLog" }) do
		out["fns:" .. name] = fnList(rawget(_G, name))
	end
	local quest, logIndex
	local QL = rawget(_G, "C_QuestLog")
	if type(QL) == "table" and QL.GetNumQuestLogEntries and QL.GetInfo then
		local ok, n = pcall(QL.GetNumQuestLogEntries)
		for i = 1, (ok and tonumber(n) or 0) do
			local ok2, info = pcall(QL.GetInfo, i)
			if ok2 and type(info) == "table" and not info.isHeader and info.questID then
				quest, logIndex = info.questID, i
				out["C_QuestLog.GetInfo(first quest)"] = describe(info)
				break
			end
		end
	end
	out["first quest id"] = describe(quest)
	local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local q = quest or 0
	local calls = {
		{ "C_QuestLog.GetQuestObjectives", q }, { "C_QuestLog.GetTitleForQuestID", q }, { "C_QuestLog.GetQuestDifficultyLevel", q },
		{ "C_QuestLog.IsComplete", q }, { "C_QuestLog.ReadyForTurnIn", q }, { "C_QuestLog.GetQuestTagInfo", q }, { "GetQuestTagInfo", q },
		{ "C_QuestLog.GetSuggestedGroupSize", q }, { "C_QuestLog.IsQuestTrivial", q }, { "C_QuestLog.GetLogIndexForQuestID", q },
		{ "C_QuestLog.GetNextWaypoint", q }, { "C_QuestLog.GetNextWaypointText", q }, { "C_QuestLog.GetDistanceSqToQuest", q },
		{ "C_QuestLog.GetQuestsOnMap", mapID or 0 }, { "C_QuestLog.GetZoneStoryInfo", mapID or 0 }, { "C_QuestLog.GetSelectedQuest" },
		{ "C_QuestLog.GetQuestLogPortraitGiver" }, { "C_QuestLog.GetRequiredMoney", q }, { "C_QuestLog.GetQuestType", q },
		{ "GetQuestLogQuestText", logIndex or 1 }, { "GetQuestLogLeaderBoard", 1, logIndex or 1 }, { "GetQuestDifficultyColor", 15 },
		{ "GetNumQuestLogChoices", q }, { "GetQuestLogChoiceInfo", 1 }, { "GetNumQuestLogRewards", q }, { "GetQuestLogRewardInfo", 1, q },
		{ "GetQuestLogRewardMoney", q }, { "GetQuestLogRewardXP", q }, { "GetQuestLogItemLink", "choice", 1 },
		{ "C_Map.CanSetUserWaypointOnMap", mapID or 0 }, { "C_Map.HasUserWaypoint" }, { "C_Map.GetMapInfo", mapID or 0 },
		{ "C_SuperTrack.GetSuperTrackedQuestID" }, { "C_SuperTrack.IsSuperTrackingAnything" },
		{ "GetInstanceInfo" }, { "IsInInstance" }, { "GetQuestGreenRange" }, { "UnitQuestTrivialLevelRange", "player" },
		{ "C_AddOns.GetNumAddOns" }, { "C_TradeSkillUI.GetAllProfessionTradeSkillLines" },
	}
	for _, c in ipairs(calls) do
		out[c[1] .. "(" .. tostring(c[2] or "") .. ")"] = try(g(c[1]), select(2, unpack(c)))
	end
	-- Which of these globals exist (type only): the quest window's text, linking, hooking.
	local kinds = {}
	for _, name in ipairs({ "GetQuestText", "GetObjectiveText", "GetRewardText", "GetProgressText", "GetNumQuestChoices", "GetQuestItemLink",
		"GetQuestItemInfo", "GetQuestID", "QuestInfo_Display", "QuestMapFrame_ShowQuestDetails", "QuestLog_Update", "QuestLog_SetSelection",
		"ChatEdit_InsertLink", "ChatEdit_GetActiveWindow", "HandleModifiedItemClick", "hooksecurefunc", "TooltipDataProcessor",
		"CombatLogGetCurrentEventInfo", "InCombatLockdown", "GameTooltip_AddQuestRewardsToTooltip", "PawnVersion", "Questie",
		"QuestieLoader", "ElvUI", "Bagnon", "AdiBags", "Baganator" }) do
		kinds[name] = type(rawget(_G, name))
	end
	out.globals = kinds
	local TDP = rawget(_G, "TooltipDataProcessor")
	out["TooltipDataProcessor fns"] = fnList(TDP)
	out["Enum.TooltipDataType"] = Enum and describe(Enum.TooltipDataType) or "missing"
	local tip = rawget(_G, "GameTooltip")
	if tip and tip.HasScript then
		local ok, has = pcall(tip.HasScript, tip, "OnTooltipSetItem")
		out["GameTooltip:HasScript(OnTooltipSetItem)"] = describe(ok and has)
	end
	-- The game windows of §2.1: whether each exists now (some load on demand), is shown, is protected.
	local frames = {}
	for _, name in ipairs({ "QuestFrame", "QuestFrameDetailPanel", "QuestInfoFrame", "QuestInfoDescriptionText", "QuestInfoObjectivesText",
		"QuestInfoRewardsFrame", "QuestLogFrame", "QuestLogDetailFrame", "QuestLogDetailScrollFrame", "QuestLogPopupDetailFrame",
		"QuestMapFrame", "QuestMapDetailsScrollFrame", "WorldMapFrame", "ObjectiveTrackerFrame", "QuestWatchFrame",
		"CharacterFrame", "PaperDollFrame", "CharacterHeadSlot", "CharacterMainHandSlot", "PlayerSpellsFrame", "ClassTalentFrame",
		"PlayerTalentFrame", "SpellBookFrame", "ClassTrainerFrame", "MerchantFrame", "GroupLootFrame1", "ProfessionsFrame",
		"TradeSkillFrame", "ContainerFrame1", "ContainerFrameCombinedBags", "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1",
		"Minimap", "MinimapCluster", "ChatFrame1EditBox" }) do
		local f = rawget(_G, name)
		if type(f) ~= "table" then
			frames[name] = "nil"
		else
			local bits = {}
			if f.GetObjectType then local ok, t = pcall(f.GetObjectType, f); bits[#bits + 1] = ok and tostring(t) or "?" end
			if f.IsShown then local ok, s = pcall(f.IsShown, f); bits[#bits + 1] = (ok and s) and "shown" or "hidden" end
			if f.IsProtected then local ok, p = pcall(f.IsProtected, f); if ok and p then bits[#bits + 1] = "protected" end end
			frames[name] = table.concat(bits, ",")
		end
	end
	out.frames = frames
	-- The load-on-demand UIs those windows live in.
	local AO = rawget(_G, "C_AddOns")
	local lod = {}
	for _, name in ipairs({ "Blizzard_TrainerUI", "Blizzard_PlayerSpells", "Blizzard_ClassTalentUI", "Blizzard_TalentUI", "Blizzard_Professions",
		"Blizzard_TradeSkillUI", "Blizzard_QuestLog", "Blizzard_WorldMap", "Blizzard_ObjectiveTracker" }) do
		local ok, loaded = pcall(AO and AO.IsAddOnLoaded or IsAddOnLoaded, name)
		lod[name] = ok and tostring(loaded) or "?"
	end
	out.lodUI = lod
	-- Other addons that are loaded, by folder name only, to plan around their decorations (Questie, Pawn, bags).
	local loaded = {}
	if AO and AO.GetNumAddOns and AO.GetAddOnInfo and AO.IsAddOnLoaded then
		local ok, n = pcall(AO.GetNumAddOns)
		for i = 1, (ok and tonumber(n) or 0) do
			local ok2, name = pcall(AO.GetAddOnInfo, i)
			local ok3, on = pcall(AO.IsAddOnLoaded, i)
			if ok2 and ok3 and on and type(name) == "string" and not name:find("^Spellmind_S") and not name:find("^NeverQuestAlone_S") then
				loaded[#loaded + 1] = name
			end
			if #loaded >= 80 then break end
		end
	end
	table.sort(loaded)
	out.addons = table.concat(loaded, ",")
	-- Pawn's public functions, if Pawn is there (its API is what we may use; its files aren't read).
	local pawn = {}
	for name, v in pairs(_G) do
		if type(name) == "string" and type(v) == "function" and name:find("^Pawn") then pawn[#pawn + 1] = name end
	end
	table.sort(pawn)
	for i = #pawn, 61, -1 do pawn[i] = nil end
	out["Pawn fns"] = table.concat(pawn, ",")
end

-- Round 5 (the gear advisor's upgrades, 2026-11-11): the Dungeon Journal. Does Forever have it, with
-- classic dungeons and their loot? It loads the journal's own Blizzard addon (load on demand, read
-- only) and reads the first tiers, instances, an encounter and its loot. Nothing is opened on screen.
function ns.ProbeRound5(out, try, g)
	local AO = rawget(_G, "C_AddOns")
	out["EJ addon exists"] = describe(AO and AO.DoesAddOnExist and select(2, pcall(AO.DoesAddOnExist, "Blizzard_EncounterJournal")))
	out["EJ addon loaded before"] = describe(AO and AO.IsAddOnLoaded and select(2, pcall(AO.IsAddOnLoaded, "Blizzard_EncounterJournal")))
	if AO and AO.LoadAddOn then out["EJ LoadAddOn"] = try(AO.LoadAddOn, "Blizzard_EncounterJournal") end
	out["fns:C_EncounterJournal"] = fnList(rawget(_G, "C_EncounterJournal"))
	local ej = {}
	for name, v in pairs(_G) do
		if type(name) == "string" and type(v) == "function" and name:find("^EJ_") then ej[#ej + 1] = name end
	end
	table.sort(ej)
	out["EJ_ globals"] = table.concat(ej, ",")
	local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	out["EJ_GetInstanceForMap(here)"] = try(g("EJ_GetInstanceForMap"), map or 0)
	out["EJ_GetNumTiers()"] = try(g("EJ_GetNumTiers"))
	out["EJ_GetCurrentTier()"] = try(g("EJ_GetCurrentTier"))
	local tiers = {}
	local nt = select(2, pcall(g("EJ_GetNumTiers") or function() return 0 end)) or 0
	local firstInstance
	for t = 1, math.min(tonumber(nt) or 0, 4) do
		pcall(g("EJ_SelectTier"), t)
		local names = { tier = describe(select(2, pcall(g("EJ_GetTierInfo"), t))) }
		for i = 1, 6 do
			local ok, id, name = pcall(g("EJ_GetInstanceByIndex"), i, false)
			if ok and id then
				names[#names + 1] = tostring(id) .. "=" .. tostring(name)
				firstInstance = firstInstance or id
			end
		end
		tiers["tier" .. t] = names
	end
	out["EJ tiers (dungeons)"] = tiers
	if firstInstance then
		pcall(g("EJ_SelectInstance"), firstInstance)
		out["EJ_GetInstanceInfo(first)"] = try(g("EJ_GetInstanceInfo"), firstInstance)
		out["EJ_GetEncounterInfoByIndex(1)"] = try(g("EJ_GetEncounterInfoByIndex"), 1)
		local ok, _, _, encounterID = pcall(g("EJ_GetEncounterInfoByIndex"), 1)
		if ok and encounterID then pcall(g("EJ_SelectEncounter"), encounterID) end
		out["EJ_GetNumLoot()"] = try(g("EJ_GetNumLoot"))
		local CEJ = rawget(_G, "C_EncounterJournal")
		out["C_EncounterJournal.GetLootInfoByIndex(1)"] = try(CEJ and CEJ.GetLootInfoByIndex, 1)
		out["EJ_GetLootInfoByIndex(1)"] = try(g("EJ_GetLootInfoByIndex"), 1)
	end
	-- And the merchant and quest turn-in reward functions the vendor helper and the picks badge use.
	local kinds = {}
	for _, name in ipairs({ "GetMerchantNumItems", "GetMerchantItemLink", "GetQuestItemLink", "GetNumQuestChoices", "GetQuestItemInfo",
		"GetQuestReward", "GetSellValue", "PaperDollItemSlotButton_Update", "PaperDollFrame_UpdateStats" }) do
		kinds[name] = type(rawget(_G, name))
	end
	out["globals round 5"] = kinds
end

-- Round 6 (dungeon prep, 2026-11-12): which dungeons the game itself knows, with their levels (the
-- LFG tool's activities, the dungeon finder), the instance you're in, and dungeon entrances on the
-- map. Forever has its own dungeons (the Hall of Thanes), so a built-in list would be wrong.
function ns.ProbeRound6(out, try, g)
	out["GetInstanceInfo()"] = try(g("GetInstanceInfo"))
	out["IsInInstance()"] = try(g("IsInInstance"))
	local LL = rawget(_G, "C_LFGList")
	out["fns:C_LFGList"] = fnList(LL)
	out["fns:C_LFGInfo"] = fnList(rawget(_G, "C_LFGInfo"))
	if type(LL) == "table" then
		out["C_LFGList.GetAvailableCategories()"] = try(LL.GetAvailableCategories)
		out["C_LFGList.GetAvailableActivities(2)"] = try(LL.GetAvailableActivities, 2)
		local ok, acts = pcall(LL.GetAvailableActivities, 2)
		if ok and type(acts) == "table" then
			local first = {}
			for i = 1, math.min(#acts, 4) do
				first["activity " .. tostring(acts[i])] = try(LL.GetActivityInfoTable, acts[i])
			end
			out["C_LFGList.GetActivityInfoTable(first 4)"] = first
		end
	end
	local kinds = {}
	for _, name in ipairs({ "GetLFGDungeonInfo", "GetNumRandomDungeons", "GetLFDChoiceOrder", "GetLFGDungeonNumEncounters",
		"GetInstanceInfo", "GetNumSavedInstances", "GetSavedInstanceInfo" }) do
		kinds[name] = type(rawget(_G, name))
	end
	out["globals round 6"] = kinds
	out["GetLFGDungeonInfo(1)"] = try(g("GetLFGDungeonInfo"), 1)
	local map = tonumber((select(2, pcall(g("C_Map.GetBestMapForUnit"), "player"))))
	local CEJ = rawget(_G, "C_EncounterJournal")
	if map then
		out["C_EncounterJournal.GetDungeonEntrancesForMap(here)"] = try(CEJ and CEJ.GetDungeonEntrancesForMap, map)
		-- The continent too: entrances are often on the zone's parent map.
		local okInfo, info = pcall(g("C_Map.GetMapInfo"), map)
		if okInfo and type(info) == "table" and info.parentMapID then
			out["C_EncounterJournal.GetDungeonEntrancesForMap(parent)"] = try(CEJ and CEJ.GetDungeonEntrancesForMap, info.parentMapID)
		end
	end
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
	ns.ProbeRound4(out, try, g)
	pcall(ns.ProbeRound5, out, try, g)
	pcall(ns.ProbeRound6, out, try, g)
	ns.db.probe = out
	ns.db.probeAt = time()
	local n = 0
	for _ in pairs(out) do n = n + 1 end
	return n
end
